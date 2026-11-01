/// A task as it is kept: the fields of ADR-0141 written only when they hold something, and absent ones read as empty, so records from
/// before it read unchanged.
extension SessionTask: Codable {
    private enum Key: String, CodingKey {
        // @dl:accept -- the tasks and the ideas are two lists of one store (ADR-0141): their reads, inputs, tools and records share a shape over different fields
        case id, title, detail, state, blockedBy, related, tags, made, closed
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: Key.self)
        self.init(
            id: try container.decode(Int.self, forKey: .id),
            title: try container.decode(String.self, forKey: .title),
            detail: try container.decode(String.self, forKey: .detail),
            state: try container.decode(TaskState.self, forKey: .state),
            blockedBy: try container.decode([Int].self, forKey: .blockedBy),
            related: try container.decode([Int].self, forKey: .related),
            tags: try container.decodeIfPresent([String].self, forKey: .tags) ?? [],
            made: try container.decodeIfPresent(Int.self, forKey: .made),
            closed: try container.decodeIfPresent(Int.self, forKey: .closed)
            // @dl:accept -- the tasks and the ideas are two lists of one store (ADR-0141): their reads, inputs, tools and records share a shape over different fields
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: Key.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        // @dl:accept -- the tasks and the ideas are two lists of one store (ADR-0141): their reads, inputs, tools and records share a shape over different fields
        try container.encode(detail, forKey: .detail)
        try container.encode(state, forKey: .state)
        try container.encode(blockedBy, forKey: .blockedBy)
        try container.encode(related, forKey: .related)
        if !tags.isEmpty { try container.encode(tags, forKey: .tags) }
        try container.encodeIfPresent(made, forKey: .made)
        try container.encodeIfPresent(closed, forKey: .closed)
    }
}
