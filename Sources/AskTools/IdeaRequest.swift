internal import AskAgentCore

/// An `ideas` call (ADR-0141), in the shape of a `tasks` call: `changes` (marks), a `read`, or both.
public struct IdeaRequest: Decodable, Sendable {
    // @dl:accept -- the tasks and the ideas are two lists of one store (ADR-0141): their reads, inputs, tools and records share a shape over different fields
    let changes: [IdeaPlanner.Mark]?
    let read: IdeaQuery?

    public init(from decoder: any Decoder) throws {
        let call = try ListCall.decode(decoder, IdeaMarkInput.self, IdeaReadInput.self)
        changes = call.changes?.map(\.mark)
        read = call.read?.query
    }
}
