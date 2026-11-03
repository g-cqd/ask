/// The person's notes (roadmap 0180), kept beside the session as the tasks are (ADR-0140), in the order they were had.
// @dl:accept -- the tasks and the ideas are two lists of one store: their declarations, add guards and id lookups share a shape over different fields
public struct IdeaList: ChangeList {
    public static let suffix = "ideas"
    public static let workspaceName = "ideas.ask"

    public private(set) var ideas: [Idea] = []
    /// One more than the largest id ever given, so a number is never given twice.
    public private(set) var nextID = 1

    public init() {}

    public func idea(_ id: Int) -> Idea? { ideas.first { $0.id == id } }

    /// How many the model has not seen.
    public var newCount: Int { ideas.count { $0.state == .new } }

    /// The change that keeps `text`, verbatim, as the next note, had at `time`.
    public func adding(_ text: String, at time: Int) -> IdeaChange {
        // @dl:accept -- the tasks and the ideas are two lists of one store (ADR-0141): their reads, inputs, tools and records share a shape over different fields
        .add(Idea(id: nextID, text: text, made: time, edited: nil, state: .new))
    }

    /// Makes `change`, or refuses it and leaves the notes as they were.
    // @dl:accept -- the tasks and the ideas are two lists of one store: their declarations, add guards and id lookups share a shape over different fields
    public mutating func apply(_ change: IdeaChange) throws(IdeaListError) {
        var next = self
        try next.make(change)
        self = next
    }

    private mutating func make(_ change: IdeaChange) throws(IdeaListError) {
        switch change {
            case .add(let idea):
                guard idea.id >= nextID else { throw .taken(idea.id) }
                guard !idea.text.isBlank else { throw .emptyText }
                ideas.append(idea)
                nextID = idea.id + 1
            case .edit(let id, let text, let time):
                let index = try place(id)
                guard !text.isBlank else { throw .emptyText }
                ideas[index].text = text
                ideas[index].edited = time
            // @dl:accept -- the tasks and the ideas are two lists of one store: their declarations, add guards and id lookups share a shape over different fields
            case .state(let id, let state): ideas[try place(id)].state = state
            case .link(let id, let task):
                let index = try place(id)
                if !ideas[index].tasks.contains(task) { ideas[index].tasks.append(task) }
            case .remove(let id):
                ideas.remove(at: try place(id))
            case .batch(let changes):
                for change in changes {
                    if case .batch = change { throw .nested }
                    try make(change)
                }
        }
    }

    private func place(_ id: Int) throws(IdeaListError) -> Int {
        guard let index = ideas.firstIndex(where: { $0.id == id }) else { throw .unknownIdea(id) }
        return index
    }
}
