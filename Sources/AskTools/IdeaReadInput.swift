// @dl:accept -- the tasks and the ideas are two lists of one store (ADR-0141): their reads, inputs, tools and records share a shape over different fields
internal import AskAgentCore

/// A notes `read`.
// @dl:accept -- the tasks and the ideas are two lists of one store (ADR-0141): their reads, inputs, tools and records share a shape over different fields
struct IdeaReadInput: Decodable {
    let query: IdeaQuery

    // @dl:accept -- the tasks and the ideas are two lists of one store (ADR-0141): their reads, inputs, tools and records share a shape over different fields
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: RecordKey.self)
        try container.only(["view", "ids", "text", "limit"], in: "read", for: "a read")
        // @dl:accept -- the tasks and the ideas are two lists of one store (ADR-0141): their reads, inputs, tools and records share a shape over different fields
        guard let view = IdeaQuery.View(rawValue: try container.field("view", String.self) ?? "open") else {
            throw ToolInputError("read: view is new, open, all or summary.")
        }
        query = IdeaQuery(
            view: view,
            ids: try container.refs("ids", prefix: "n", in: "read") ?? [],
            text: try container.field("text"),
            limit: try container.field("limit") ?? ListLimits.defaultReadLimit
        )
    }
}
