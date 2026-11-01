public import AskAI
public import AskAgentCore

/// `tasks` (ADR-0140, roadmap 0179): the session's task list, read and changed by the model when it calls this; nothing of it is sent on
/// other turns. Ids are `t1`, `t2`, … in the order made.
public struct TasksTool: ArgumentTool {
    public typealias Arguments = TaskRequest

    public let definition = ToolDefinition(
        name: "tasks",
        description: """
            The session's task list, kept outside your context: read it at the start of a piece of work. action: list (open and in \
            progress; "all": true for done ones too), show (one task's description), add (title, optional detail, blocked_by, \
            related), edit (title and/or detail), start, done, reopen, remove, move (before or after another), link or unlink \
            (blocked_by or related another). Ids are t1, t2, … A task is blocked while one it waits on is not done.
            """
    ) {
        ToolProperty.string("action")
        ToolProperty.string("id").optional
        ToolProperty.string("title").optional
        ToolProperty.string("detail").optional
        ToolProperty.boolean("all").optional
        ToolProperty.string("before").optional
        ToolProperty.string("after").optional
        ToolProperty.schema("blocked_by", #"{"type":["string","array"],"items":{"type":"string"}}"#).optional
        ToolProperty.schema("related", #"{"type":["string","array"],"items":{"type":"string"}}"#).optional
    }

    private let board: TaskBoard

    public init(board: TaskBoard) { self.board = board }

    public func run(_ request: TaskRequest, in context: ToolContext) async throws(ToolFailure) -> ToolOutput {
        guard board.isAttached else {
            throw ToolFailure("No task list is open for this session; the person can see why with /tasks.")
        }
        do {
            return try perform(request)
        } catch let error as TaskListError {
            throw ToolFailure(Self.words(error))
        } catch let error as ToolFailure {
            throw error
        } catch {
            throw ToolFailure("The task list could not be changed: \(error)")
        }
    }

    private func perform(_ request: TaskRequest) throws -> ToolOutput {
        switch request.action {
            case "list": return ToolOutput(try board.current()?.listing(all: request.all ?? false) ?? "")
            case "show":
                let id = try request.taskID()
                guard let shown = try board.current()?.showing(id) else { throw TaskListError.unknownTask(id) }
                return ToolOutput(shown)
            case "add":
                guard let title = request.title else { throw ToolFailure("add needs a title.") }
                let list = try board.change {
                    $0.adding(
                        title: title,
                        detail: request.detail ?? "",
                        blockedBy: request.blockedBy?.values ?? [],
                        related: request.related?.values ?? []
                    )
                }
                return ToolOutput(list.flatMap { list in list.tasks.last.map(list.line) } ?? "")
            default:
                let id = try request.taskID()
                let change = try request.change(for: id)
                let list = try board.change { _ in change }
                return ToolOutput(list.flatMap { list in list.task(id).map(list.line) } ?? "Removed t\(id).")
        }
    }

    static func words(_ error: TaskListError) -> String {
        switch error {
            case .unknownTask(let id): "There is no task t\(id); list them to see their ids."
            case .taken(let id): "t\(id) was given already; add the task again."
            case .emptyTitle: "A task needs a title."
            case .cycle: "That would make a task wait on itself."
        }
    }
}
