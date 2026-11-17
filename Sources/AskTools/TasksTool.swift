public import AskAI
public import AskAgentCore

/// `tasks` (ADR-0140, ADR-0141): the session's task list, read and changed when the model calls it; nothing of it is sent on other turns.
/// A call holds a batch of changes, all made or none, each safe to repeat, and a read.
public struct TasksTool: ArgumentTool {
    public typealias Arguments = TaskRequest

    public let definition = ListToolSchema.definition(
        name: "tasks",
        description: """
            Your task list, outside your context: read it when you start work.
            A call makes changes, a read, or both. Changes are made all or none, and repeating one is harmless. An id is t3; \
            several are space-separated, with ranges: t3 t5-t9; @1 is this call's first add.
            """,
        change: Self.change,
        changes: "Changes, made in order.",
        read: Self.read
    )

    private static let read = ListToolSchema.read(
        views: ["open", "done", "all", "summary"],
        view: "open unless given.",
        noun: "tasks"
    )

    private static let change: [ToolSchema.Field] = [
        // @dl:accept -- the tasks and the ideas are two lists of one store (ADR-0141): their reads, inputs, tools and records share a shape over different fields
        .init(
            "op",
            .choice(["add", "edit", "state", "move", "link", "unlink", "remove"]),
            """
            add a task; edit one task's title, detail or tags; state sets the state of some; move puts one before another; \
            link and unlink set blocked_by and related; remove.
            """
        ),
        .init("ids", .string(), "The tasks to change; one for edit and move, none for add."),
        // @dl:accept -- the tasks and the ideas are two lists of one store (ADR-0141): their reads, inputs, tools and records share a shape over different fields
        .init("title", .string(), "At most \(ListLimits.titleLength) characters; the rest goes in detail."),
        .init("detail", .string(), "More about the task."),
        .init(
            "state",
            .choice(["open", "in_progress", "done"]),
            "For add and state."
        ),
        .init(
            "tags",
            .string(),
            "Space-separated words: lowercase letters, digits, dashes."
        ),
        .init("blocked_by", .string(), "Ids of tasks it waits for."),
        .init("related", .string(), "Ids of tasks that bear on it."),
        .init("before", .string(), "For move: an id, or end.")
    ]

    private let board: TaskBoard
    private let now: @Sendable () -> Int

    public init(board: TaskBoard, now: @escaping @Sendable () -> Int = { ListTime.now }) {
        self.board = board
        self.now = now
    }

    public func run(_ request: TaskRequest, in context: ToolContext) async throws(ToolFailure) -> ToolOutput {
        let time = now()
        return try ListToolRun.run(
            board,
            missing: "No task list is open for this session; the person can see why with /tasks.",
            plan: request.changes.map { edits in
                { list in
                    let plan = try TaskPlanner.plan(edits, on: list, at: time)
                    return (plan.change, plan.report.summary)
                }
            },
            read: request.read.map { query in { list in try query.answer(list) } }
        )
    }
}
