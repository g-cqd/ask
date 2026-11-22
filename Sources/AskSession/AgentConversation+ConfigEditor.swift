internal import AskAgentCore
internal import AskTUI
internal import Foundation
internal import Synchronization

extension AgentConversation {
    /// The path and scope of one interactive configuration editor.
    func configEditorPath(_ scope: ConfigEditor.Scope) -> (path: String, isProject: Bool) {
        switch scope {
            case .user: (source.loader.userPath, false)
            case .project: (source.loader.projectPath, true)
        }
    }

    /// Opens the editor for `scope`, or reports why the file cannot be edited.
    func openConfigEditor(_ scope: ConfigEditor.Scope, update: @Sendable (ConversationUpdate) -> Void) async {
        let target = configEditorPath(scope)
        do {
            let editor = try ConfigEditor(path: target.path, isProject: target.isProject)
            update(
                .configEditor(
                    Self.configSnapshot(editor, trustPath: source.loader.trustPath, required: requirement(of:))
                )
            )
        } catch {
            update(.notice("Cannot edit \(target.path): \(error)", isError: true))
        }
    }

    /// The organisation's document requiring the key at `path`, if any (ADR-0168).
    func requirement(of path: [String]) -> String? {
        current.withLock { $0.settings.configuration.requirement(of: path.joined(separator: ".")) }
    }

    /// The rows and warnings the screen shows for `editor`; a row the organisation requires (`required` names its document) is not
    /// editable, since a value written here would change nothing.
    static func configSnapshot(
        _ editor: ConfigEditor,
        trustPath: String,
        required: ([String]) -> String? = { _ in nil }
    ) -> ConfigEditorSnapshot {
        var locked: [String] = []
        let rows = editor.settings.map { setting in
            let requiredBy = required(setting.path)
            if let requiredBy { locked.append("\(setting.path.joined(separator: ".")) (\(requiredBy))") }
            return ConfigSettingRow(
                path: setting.path,
                title: setting.title,
                value: setting.value,
                choices: setting.choices,
                editable: setting.editable && requiredBy == nil
            )
        }
        var warnings = editor.warnings.map {
            "\($0) is not known to ask; it is preserved, but ask refuses the file until it is removed."
        }
        if !locked.isEmpty {
            warnings.append(
                "Your organisation requires " + locked.joined(separator: ", ")
                    + ": what is written here does not change them."
            )
        }
        if editor.isProject {
            let bytes = (try? Data(contentsOf: URL(fileURLWithPath: editor.path))).map { [UInt8]($0) }
            let standing: ProjectTrust.Standing? = {
                guard let bytes, let trust = try? ProjectTrust.load(trustPath) else { return nil }
                return trust.standing(of: editor.path, bytes: bytes)
            }()
            if standing != .trusted {
                warnings.append(
                    "A project's file applies only after `ask trust` here, for the bytes as they are when you trust it."
                )
            }
        }
        return ConfigEditorSnapshot(scope: editor.scope.rawValue, file: editor.path, rows: rows, warnings: warnings)
    }

    /// Commits one row, then reads the file again and refreshes settings so the next prompt uses the validated result.
    func commitConfig(
        scope: String,
        path: [String],
        value: String,
        update: @Sendable (ConversationUpdate) -> Void
    ) async {
        guard let parsedScope = ConfigEditor.Scope(rawValue: scope) else {
            update(.notice("Unknown configuration scope \"\(scope)\".", isError: true))
            return
        }
        let target = configEditorPath(parsedScope)
        if let requiredBy = requirement(of: path) {
            update(
                .notice(
                    "Not saved: your organisation requires \(path.joined(separator: ".")) (\(requiredBy)).",
                    isError: true
                )
            )
            return
        }
        do {
            let editor = try ConfigEditor(path: target.path, isProject: target.isProject)
            let typed = try editor.value(value, at: path)
            try editor.commit(path: path, value: typed)
            let saved = try ConfigEditor(path: target.path, isProject: target.isProject)
            update(
                .configEditor(
                    Self.configSnapshot(saved, trustPath: source.loader.trustPath, required: requirement(of:))
                )
            )
            update(.notice("Saved \(path.joined(separator: ".")) to \(target.path).", isError: false))
            await refreshSettings(update: update)
        } catch {
            update(.notice("Not saved: \(error)", isError: true))
        }
    }
}
