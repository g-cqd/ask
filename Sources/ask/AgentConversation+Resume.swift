internal import AskAgentCore
internal import AskTUI
internal import Foundation
internal import Synchronization
internal import System

extension AgentConversation {
    /// Opens the replacement before releasing the old writer, so lookup/open/lock failure changes nothing.
    func resumeSession(arguments: String, update: @Sendable (ConversationUpdate) -> Void) async {
        guard !arguments.isEmpty else {
            listSessions(update: update)
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

    /// Lists this project's sessions without opening a writer or selecting one.
    private func listSessions(update: @Sendable (ConversationUpdate) -> Void) {
        let listed = directory.sessions()
        guard !listed.isEmpty else {
            update(.notice("No sessions in this project yet.", isError: false))
            return
        }
        var lines = ["Sessions (newest first). Choose with /resume NAME, PREFIX or PATH:"]
        let currentPath = session.withLock { $0?.path }
        for item in listed.prefix(20) {
            let first =
                SessionSummary(readingFrom: item.path)?.firstPrompt.map { Sessions.oneLine($0, limit: 60) } ?? ""
            let mark = item.path == currentPath ? " (current)" : ""
            lines.append("\(item.name)\(mark)  \(first)")
        }
        if listed.count > 20 {
            lines.append("Showing 20 of \(listed.count); ask sessions --limit N lists more.")
        }
        update(.notice(lines.joined(separator: "\n"), isError: false))
    }
}
