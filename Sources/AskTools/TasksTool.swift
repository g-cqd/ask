public import AskAI
public import AskAgentCore

/// `tasks` (ADR-0140, ADR-0141): the session's task list, read and changed when the model calls it; nothing of it is sent on other turns.
/// A call holds a batch of changes, all made or none, each safe to repeat, and a read.
public struct TasksTool: ArgumentTool {
    public typealias Arguments = TaskRequest

    public let definition = ToolDefinition(
        name: "tasks",
        description: """
            Your task list, outside your context: read it when you start work. Send changes, a read, or both; changes are all \
            or none, and repeating one is harmless. Ids and tags are space-separated: t3 t5-t9, @1 for this call's first add. \
            Reading ids shows them in full.
            """,
        fields: [
            .init("changes", .array(.object(Self.change))),
            .init("read", .object(Self.read))
        ]
    )

    private static let change: [ToolSchema.Field] = [
        // @dl:accept -- the tasks and the ideas are two lists of one store (ADR-0141): their reads, inputs, tools and records share a shape over different fields
        .init("op", .choice(["add", "edit", "state", "move", "link", "unlink", "remove"])), .init("ids", .string()),
        // @dl:accept -- the tasks and the ideas are two lists of one store (ADR-0141): their reads, inputs, tools and records share a shape over different fields
        .init("title", .string()), .init("detail", .string()), .init("state", .choice(["open", "in_progress", "done"])),
        .init("tags", .string()), .init("blocked_by", .string()), .init("related", .string()),
        .init("before", .string())
    ]
    private static let read: [ToolSchema.Field] = [
        // @dl:accept -- the tasks and the ideas are two lists of one store (ADR-0141): their reads, inputs, tools and records share a shape over different fields
        .init("view", .choice(["open", "done", "all", "summary"])), .init("ids", .string()), .init("text", .string()),
        .init("limit", .integer())
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
