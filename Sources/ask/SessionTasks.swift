internal import AskAgentCore
internal import Synchronization

/// The task list of the session in use (ADR-0140, roadmap 0179), one for the process: the `tasks` tool and `/tasks` read it, and it
/// follows the session as one is made, resumed, forked or replaced.
enum SessionTasks {
    static let board = TaskBoard()
    /// Why the session's list could not be opened, for `/tasks` to say.
    static let problem = Mutex<String?>(nil)

    /// Uses `recorder`'s list, or none; why it could not be opened, when it could not.
    static func follow(_ recorder: SessionRecorder?, scope: TaskScope) -> String? {
        let reason = attach(recorder, scope: scope)
        problem.withLock { $0 = reason }
        return reason
    }

    /// The list of the session in use, or why there is none.
    static func answer(to arguments: String) -> String {
        do {
            if let list = try board.current() { return list.answer(to: arguments) }
        } catch {
            return "The task list could not be read: \(error)"
        }
        return problem.withLock { $0 } ?? "No task list yet: it opens with the session, at the first prompt."
    }

    private static func attach(_ recorder: SessionRecorder?, scope: TaskScope) -> String? {
        guard let recorder else {
            board.detach()
            return nil
        }
        do {
            let keyring = SessionKeyAccess.keyring
            switch scope {
                case .session:
                    try board.attach(
                        sessionPath: recorder.path,
                        format: recorder.format,
                        keyring: keyring,
                        scope: scope
                    )
                case .workspace:
                    let format = SessionKeyAccess.protection.format
                    try board.attach(sessionPath: recorder.path, format: format, keyring: keyring, scope: scope)
                    try board.convert(to: format)
            }
            return nil
        } catch {
            board.detach()
            return "The task list could not be opened: \(error)"
        }
    }
}
