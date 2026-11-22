internal import AskAgentCore
internal import AskTUI
internal import Synchronization

/// The task list and the notes of a conversation's session (ADR-0140, roadmaps 0179 and 0180): their tools and commands read them,
/// and they follow the session as one is made, resumed, forked or replaced.
///
/// One of each for a conversation, not for the process (ADR-0154): `ask serve` holds several conversations at once, and with one
/// list between them each wrote the other's session (diary 2026-11-15-06).
final class SessionTasks: Sendable {
    let board = TaskBoard()
    let ideas = IdeaBoard()
    /// Why the session's lists could not be opened, for `/tasks` and `/notes` to say.
    let problem = Mutex<String?>(nil)
    /// The done tasks whose cost was said, by the moment they were done, so each is said once a time it is done (roadmap 0239).
    let costSaid = Mutex<[Int: Int]>([:])

    /// Uses `recorder`'s lists, or none; why they could not be opened, when they could not.
    func follow(_ recorder: SessionRecorder?, scope: TaskScope) -> String? {
        let reason = Self.attach(board, to: recorder, scope: scope) ?? Self.attach(ideas, to: recorder, scope: scope)
        problem.withLock { $0 = reason }
        // The tasks already done were done before this list was followed: their cost is not said again (roadmap 0239).
        let done =
            ((try? board.current()) ?? nil)?.tasks
            .compactMap { task in (task.finished ?? task.closed).map { (task.id, $0) } } ?? []
        costSaid.withLock { $0 = Dictionary(done) { first, _ in first } }
        return reason
    }

    /// The task list of the session in use, or why there is none; a done task with what it cost, read from `tree` (roadmap 0239).
    func answer(to arguments: String, tree: SessionTree? = nil) -> String {
        let spent = { (task: SessionTask) -> String? in
            guard let tree, let spend = WorkSpend.of(task, in: tree), !spend.isEmpty else { return nil }
            return TurnSpend(spend).summary(localized: false)
        }
        do {
            if let list = try board.current() { return list.answer(to: arguments, spent: spent) }
        } catch {
            return "The task list could not be read: \(error)"
        }
        return unavailable
    }

    /// `text` with the tasks and ideas it names (`#t3`, `#i2`) attached (roadmap 0186).
    func attachReferences(_ text: String) -> String {
        let tasks = (try? board.current()) ?? nil
        let notes = (try? ideas.current()) ?? nil
        return ListReferences.attach(text, tasks: tasks, ideas: notes)
    }

    /// Whether the lists are not there only because no session has started yet (no first prompt), not because they failed to open.
    var waitsForSession: Bool { !ideas.isAttached && problem.withLock { $0 } == nil }

    /// Why a list is not there.
    var unavailable: String {
        problem.withLock { $0 } ?? "Nothing is kept yet: the session starts with the first prompt."
    }

    /// Both lists written again in `format`, as `/encrypt` changes their session's.
    func convert(to format: SessionFormat) throws {
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
