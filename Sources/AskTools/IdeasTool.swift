public import AskAI
public import AskAgentCore

/// `notes` (roadmap 0180, ADR-0141): the person's notes, saved with `/notes` while working. The model reads them when asked, or once a
/// piece of work is done, and marks them; writing and editing them is the person's alone. The shape of a `tasks` call.
public struct IdeasTool: ArgumentTool {
    public typealias Arguments = IdeaRequest

    public let definition = ListToolSchema.definition(
        name: "notes",
        description: """
            The person's notes to you: read them when asked, and when you finish work.
            A change only marks what became of some. Shaped as tasks, with ids n3 n5-n9.
            """,
        change: Self.mark,
        changes: "Marks, made in order.",
        read: ListToolSchema.read(
            views: ["new", "open", "all", "summary"],
            view: "open unless given; new: not yet acknowledged.",
            noun: "notes"
        )
    )

    private static let mark: [ToolSchema.Field] = [
        // @dl:accept -- the tasks and the ideas are two lists of one store (ADR-0141): their reads, inputs, tools and records share a shape over different fields
        .init("ids", .string(), "The notes to mark."),
        .init(
            "state",
            .choice(["acknowledged", "fulfilled", "dismissed"]),
            "acknowledged: read. fulfilled: done. dismissed: not to be done."
        ),
        .init("task", .string(), "The one task a note became: t12.")
    ]

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
