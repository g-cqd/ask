internal import AskAgentCore
internal import AskTUI
internal import Foundation
internal import Synchronization
internal import System

extension AgentConversation {
    /// Opens the replacement before releasing the old writer, so lookup/open/lock failure changes nothing.
    func resumeSession(arguments: String, update: @Sendable (ConversationUpdate) -> Void) async {
        guard !arguments.isEmpty else {
            for item in sessionPickerOpening() { update(item) }
            return
        }
        do {
            let path = try directory.resolve(arguments)
            let canonical = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
            let active = session.withLock { $0?.path }
            if let active,
                URL(fileURLWithPath: active).standardizedFileURL.resolvingSymlinksInPath().path == canonical
            {
                update(.notice("Already using session \((active as NSString).lastPathComponent).", isError: false))
                return
            }
            guard maySwitchSession("resume", update: update) else { return }
            let replacement = SessionRecorder(try SessionFile.open(at: FilePath(path)))
            guard !Task.isCancelled else {
                report(AgentError.cancelled, to: update)
                return
            }
            activateSession(replacement, update: update)
            await adoptRecords(of: replacement, update: update)
            if let notice = replacement.repairNotice { update(.notice(notice, isError: false)) }
            update(.notice("Resumed session \((replacement.path as NSString).lastPathComponent)", isError: false))
        } catch SessionFileError.inUse {
            update(.notice("Cannot resume \(arguments): this session is open in another ask.", isError: true))
        } catch {
            update(.notice("Cannot resume \(arguments): \(error)", isError: true))
        }
    }

    /// Preload startup choices: opening updates run before asynchronous effects are handled.
    func sessionPickerOpening() -> [ConversationUpdate] {
        let rows = sessionRows()
        guard !rows.isEmpty else { return [.notice("No sessions in this project yet.", isError: false)] }
        return [.choices(command: "resume", rows: rows), .fillDraft("/resume ")]
    }

    /// Searchable choices, newest first. Listing never opens a writer or selects a session.
    func sessionRows() -> [ChoiceRow] {
        let currentPath = session.withLock { $0?.path }
        return directory.sessions()
            .map { item in
                let first =
                    SessionSummary(readingFrom: item.path)?.firstPrompt.map { Sessions.oneLine($0, limit: 80) } ?? ""
                return ChoiceRow(
                    label: item.name, detail: first, arguments: item.path, isCurrent: item.path == currentPath)
            }
    }
}
