// @dl:accept -- the tasks and the ideas are two lists of one store (ADR-0141): their reads, inputs, tools and records share a shape over different fields
internal import AskAgentCore

/// `read`.
// @dl:accept -- the tasks and the ideas are two lists of one store (ADR-0141): their reads, inputs, tools and records share a shape over different fields
struct TaskReadInput: Decodable {
    let query: TaskQuery

    // @dl:accept -- the tasks and the ideas are two lists of one store (ADR-0141): their reads, inputs, tools and records share a shape over different fields
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: RecordKey.self)
        try container.only(["view", "ids", "text", "limit"], in: "read", for: "a read")
        let viewName = try container.field("view", String.self) ?? "open"
        // @dl:accept -- the tasks and the ideas are two lists of one store (ADR-0141): their reads, inputs, tools and records share a shape over different fields
        guard let view = TaskQuery.View(rawValue: viewName) else {
            throw ToolInputError("read: view is open, done, all or summary.")
        }
        query = TaskQuery(
            view: view,
            ids: try container.refs("ids", prefix: "t", in: "read") ?? [],
            text: try container.field("text"),
            limit: try container.field("limit") ?? ListLimits.defaultReadLimit
        )
    }
}
