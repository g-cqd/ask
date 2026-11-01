public import AskAI
public import AskAgentCore

/// `ideas` (roadmap 0180): the person's ideas, saved with `/idea` while working. The model reads them when asked, or once a piece of
/// work is done, and marks them; writing and editing them is the person's alone.
// @dl:accept -- the tasks and ideas tools are two faces of one store: the declaration and the shared run read alike, the actions differ
public struct IdeasTool: ArgumentTool {
    public typealias Arguments = IdeaRequest

    public let definition = ToolDefinition(
        name: "ideas",
        description: """
            The person's ideas, saved while you worked; check them when they ask, and when you finish a task or the work. action: \
            list (open ideas, new ones counted; "all": true for fulfilled and dismissed too), show (one idea's whole text), \
            acknowledge (seen, not acted on yet), fulfil (done), dismiss (not to do), reopen (back to acknowledged). Ids are i1, \
            i2, … You cannot add or edit an idea.
            """
    ) {
        ToolProperty.string("action")
        ToolProperty.string("id").optional
        // @dl:accept -- the tasks and ideas tools are two faces of one store: the declaration and the shared run read alike, the actions differ
        ToolProperty.boolean("all").optional
    }

    private let board: IdeaBoard

    public init(board: IdeaBoard) { self.board = board }

    public func run(_ request: IdeaRequest, in context: ToolContext) async throws(ToolFailure) -> ToolOutput {
        try ListToolRun.run(
            attached: board.isAttached,
            missing: "No ideas are open for this session.",
            refusal: IdeaListError.self,
            words: Self.words
        ) { try perform(request) }
    }

    private func perform(_ request: IdeaRequest) throws -> ToolOutput {
        if request.action == "list" {
            guard let list = try board.current() else { return ToolOutput("") }
            let count = list.newCount == 0 ? "No new ideas." : "\(list.newCount) new."
            return ToolOutput(
                list.ideas.isEmpty ? list.listing(all: false) : count + "\n" + list.listing(all: request.all ?? false)
            )
        }
        let id = try request.ideaID()
        if request.action == "show" {
            guard let list = try board.current(), let idea = list.idea(id) else { throw IdeaListError.unknownIdea(id) }
            return ToolOutput(list.line(idea) + "\n\n" + idea.text)
        }
        let state = try request.state()
        let list = try board.change { _ in .state(id: id, state) }
        return ToolOutput(list.flatMap { list in list.idea(id).map { list.line($0) } } ?? "")
    }

    static func words(_ error: IdeaListError) -> String {
        switch error {
            case .unknownIdea(let id): "There is no idea i\(id); list them to see their ids."
            case .emptyText: "An idea cannot be empty."
            case .taken(let id): "i\(id) was given already."
        }
    }
}
