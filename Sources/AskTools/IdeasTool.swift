public import AskAI
public import AskAgentCore

/// `notes` (roadmap 0180, ADR-0141): the person's notes, saved with `/notes` while working. The model reads them when asked, or once a
/// piece of work is done, and marks them; writing and editing them is the person's alone. The shape of a `tasks` call.
public struct IdeasTool: ArgumentTool {
    public typealias Arguments = IdeaRequest

    public let definition = ToolDefinition(
        name: "notes",
        description: """
            The person's notes: read them when asked and when you finish work. Shaped as tasks; ids n3 n5-n9. A change sets \
            their state, and task the task one became.
            """,
        fields: [
            .init(
                "changes",
                .array(
                    .object([
                        // @dl:accept -- the tasks and the ideas are two lists of one store (ADR-0141): their reads, inputs, tools and records share a shape over different fields
                        .init("ids", .string()), .init("state", .choice(["acknowledged", "fulfilled", "dismissed"])),
                        .init("task", .string())
                    ])
                )
            ),
            .init(
                "read",
                .object([
                    // @dl:accept -- the tasks and the ideas are two lists of one store (ADR-0141): their reads, inputs, tools and records share a shape over different fields
                    .init("view", .choice(["new", "open", "all", "summary"])), .init("ids", .string()),
                    .init("text", .string()), .init("limit", .integer())
                ])
            )
        ]
    )

    private let board: IdeaBoard
    private let tasks: TaskBoard

    /// `tasks`: the list a mark's `task` is looked up in; required, so a tool built without it cannot claim a task is missing.
    public init(board: IdeaBoard, tasks: TaskBoard) {
        self.board = board
        self.tasks = tasks
    }

    public func run(_ request: IdeaRequest, in context: ToolContext) async throws(ToolFailure) -> ToolOutput {
        // The task list is read under the notes' lock, never the other way round, so the two locks cannot wait on each other.
        try ListToolRun.run(
            board,
            missing: "No notes are open for this session.",
            plan: request.changes.map { marks in
                { list in try IdeaPlanner.plan(marks, on: list, tasks: try tasks.current()) }
            },
            read: request.read.map { query in { list in try query.answer(list) } }
        )
    }
}
