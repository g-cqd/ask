internal import AskAgentCore
internal import Synchronization

/// The task list and the ideas of the session in use (ADR-0140, roadmaps 0179 and 0180), one of each for the process: their tools and
/// commands read them, and they follow the session as one is made, resumed, forked or replaced.
enum SessionTasks {
    static let board = TaskBoard()
    static let ideas = IdeaBoard()
    /// Why the session's lists could not be opened, for `/tasks` and `/ideas` to say.
    static let problem = Mutex<String?>(nil)

    /// Uses `recorder`'s lists, or none; why they could not be opened, when they could not.
    static func follow(_ recorder: SessionRecorder?, scope: TaskScope) -> String? {
        let reason = attach(board, to: recorder, scope: scope) ?? attach(ideas, to: recorder, scope: scope)
        problem.withLock { $0 = reason }
        return reason
    }

    /// The task list of the session in use, or why there is none.
    static func answer(to arguments: String) -> String {
        do {
            if let list = try board.current() { return list.answer(to: arguments) }
        } catch {
            return "The task list could not be read: \(error)"
        }
        return unavailable
    }

    /// Why a list is not there.
    static var unavailable: String {
        problem.withLock { $0 } ?? "Nothing is kept yet: the session starts with the first prompt."
    }

    /// Both lists written again in `format`, as `/encrypt` changes their session's.
    static func convert(to format: SessionFormat) throws {
        try board.convert(to: format)
        try ideas.convert(to: format)
    }

    private static func attach<List>(_ board: ChangeBoard<List>, to recorder: SessionRecorder?, scope: TaskScope)
        -> String?
    {
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
            return "The \(List.suffix) could not be opened: \(error)"
        }
    }
}
