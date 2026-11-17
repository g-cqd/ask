public import AskAI
public import AskAgentCore

/// `tasks` (ADR-0140, ADR-0141, ADR-0161): the session's task list and the person's notes, read and changed when the model calls it;
/// nothing of either is sent on other turns. A call holds a batch of changes, all made or none, each safe to repeat, and a read.
public struct TasksTool: ArgumentTool {
    public typealias Arguments = ListsRequest

    public let definition = ToolDefinition(
        name: "tasks",
        description: """
            Your task list and the person's notes to you, outside your context: read the tasks when you start work, the notes \
            when asked and when you finish.
            A call makes changes, a read, or both, on one list. Changes are made all or none, and repeating one is harmless. \
            An id is t3, a note's n3; several are space-separated, with ranges: t3 t5-t9; @1 is this call's first add.
            """,
        fields: [
            .init(
                "list",
                .choice(["tasks", "notes"]),
                "tasks unless given. notes are the person's to write: a change only sets the state of some, and names a task."
            ),
            .init("changes", .array(.object(Self.change)), "Changes, made in order."),
            .init("read", .object(Self.read), "What to show, after any changes.")
        ]
    )

    private static let read: [ToolSchema.Field] = [
        .init(
            "view",
            // @dl:accept -- a tool declares its arguments and what each says through one builder: the lists are data
            .choice(["open", "done", "all", "summary", "new"]),
            "open unless given. done: tasks only. new: notes not yet acknowledged."
        ),
        .init("ids", .string(), "These in full."),
        .init("text", .string(), "Only those matching these words."),
        .init("limit", .integer(), "At most this many: \(ListLimits.defaultReadLimit) unless given.")
    ]

    private static let change: [ToolSchema.Field] = [
        .init(
            "op",
            .choice(["add", "edit", "state", "move", "link", "unlink", "remove"]),
            """
            add a task; edit one task's title, detail or tags; state sets the state of some; move puts one before another; \
            link and unlink set blocked_by and related; remove.
            """
        ),
        .init("ids", .string(), "The tasks to change; one for edit and move, none for add."),
        .init("title", .string(), "At most \(ListLimits.titleLength) characters; the rest goes in detail."),
        .init("detail", .string(), "More about the task."),
        .init(
            "state",
            .choice(["open", "in_progress", "done", "acknowledged", "fulfilled", "dismissed"]),
            "For add and state. A note's: acknowledged (read), fulfilled (done) or dismissed (not to be done)."
        ),
        .init(
            "tags",
            .string(),
            "Space-separated words: lowercase letters, digits, dashes."
        ),
        .init("blocked_by", .string(), "Ids of tasks it waits for."),
        .init("related", .string(), "Ids of tasks that bear on it."),
        .init("before", .string(), "For move: an id, or end."),
        .init("task", .string(), "With a note's state: the one task it became, t12.")
    ]

    private let board: TaskBoard
    private let notes: IdeaBoard
    private let now: @Sendable () -> Int

    /// `notes`: the person's notes; a board that is not attached answers that none are open.
    public init(board: TaskBoard, notes: IdeaBoard = IdeaBoard(), now: @escaping @Sendable () -> Int = { ListTime.now })
    {
        self.board = board
        self.notes = notes
        self.now = now
    }

    public func run(_ request: ListsRequest, in context: ToolContext) async throws(ToolFailure) -> ToolOutput {
        switch request {
            case .tasks(let request): return try run(request)
            case .notes(let request): return try run(request)
        }
    }

    private func run(_ request: TaskRequest) throws(ToolFailure) -> ToolOutput {
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

    private func run(_ request: IdeaRequest) throws(ToolFailure) -> ToolOutput {
        // The task list is read under the notes' lock, never the other way round, so the two locks cannot wait on each other.
        try ListToolRun.run(
            notes,
            missing: "No notes are open for this session.",
            plan: request.changes.map { marks in
                { list in try IdeaPlanner.plan(marks, on: list, tasks: try board.current()) }
            },
            read: request.read.map { query in { list in try query.answer(list) } }
        )
    }
}
