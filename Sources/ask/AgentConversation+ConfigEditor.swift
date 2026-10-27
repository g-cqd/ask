internal import AskAgentCore
internal import AskTUI
internal import Foundation

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
            update(.configEditor(Self.configSnapshot(editor, trustPath: source.loader.trustPath)))
        } catch {
            update(.notice("Cannot edit \(target.path): \(error)", isError: true))
        }
    }

    /// The rows and warnings the screen shows for `editor`.
    static func configSnapshot(_ editor: ConfigEditor, trustPath: String) -> ConfigEditorSnapshot {
        let rows = editor.settings.map {
            ConfigSettingRow(
                path: $0.path, title: $0.title, value: $0.value, choices: $0.choices, editable: $0.editable)
        }
        var warnings = editor.warnings.map {
            "\($0) is not known to ask; it is preserved, but ask refuses the file until it is removed."
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
        scope: String, path: [String], value: String, update: @Sendable (ConversationUpdate) -> Void
    ) async {
        guard let parsedScope = ConfigEditor.Scope(rawValue: scope) else {
            update(.notice("Unknown configuration scope \"\(scope)\".", isError: true))
            return
        }
        let target = configEditorPath(parsedScope)
        do {
            let editor = try ConfigEditor(path: target.path, isProject: target.isProject)
            let typed = try editor.value(value, at: path)
            try editor.commit(path: path, value: typed)
            let saved = try ConfigEditor(path: target.path, isProject: target.isProject)
            update(.configEditor(Self.configSnapshot(saved, trustPath: source.loader.trustPath)))
            update(.notice("Saved \(path.joined(separator: ".")) to \(target.path).", isError: false))
            await refreshSettings(update: update)
        } catch {
            update(.notice("Not saved: \(error)", isError: true))
        }
    }
}
