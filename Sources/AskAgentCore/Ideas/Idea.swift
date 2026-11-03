/// One note (roadmap 0180), kept exactly as the person typed it.
public struct Idea: Sendable, Equatable {
    /// `n1`, `n2`, … in the order had; never reused.
    public let id: Int
    public var text: String
    /// When it was had, in seconds since 1970.
    public let made: Int
    /// When the person last edited it.
    public var edited: Int?
    public var state: IdeaState
    /// The tasks it became (ADR-0141).
    public var tasks: [Int]

    public init(id: Int, text: String, made: Int, edited: Int?, state: IdeaState, tasks: [Int] = []) {
        self.id = id
        self.text = text
        self.made = made
        self.edited = edited
        self.state = state
        self.tasks = tasks
    }

    public var name: String { "n\(id)" }
}

/// Absent `tasks`, in records from before ADR-0141, read as none.
extension Idea: Codable {
    private enum Key: String, CodingKey {
        // @dl:accept -- the tasks and the ideas are two lists of one store (ADR-0141): their reads, inputs, tools and records share a shape over different fields
        case id, text, made, edited, state, tasks
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: Key.self)
        self.init(
            id: try container.decode(Int.self, forKey: .id),
            text: try container.decode(String.self, forKey: .text),
            made: try container.decode(Int.self, forKey: .made),
            edited: try container.decodeIfPresent(Int.self, forKey: .edited),
            state: try container.decode(IdeaState.self, forKey: .state),
            tasks: try container.decodeIfPresent([Int].self, forKey: .tasks) ?? []
                // @dl:accept -- the tasks and the ideas are two lists of one store (ADR-0141): their reads, inputs, tools and records share a shape over different fields
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: Key.self)
        try container.encode(id, forKey: .id)
        // @dl:accept -- the tasks and the ideas are two lists of one store (ADR-0141): their reads, inputs, tools and records share a shape over different fields
        try container.encode(text, forKey: .text)
        try container.encode(made, forKey: .made)
        try container.encodeIfPresent(edited, forKey: .edited)
        try container.encode(state, forKey: .state)
        if !tasks.isEmpty { try container.encode(tasks, forKey: .tasks) }
    }
}
