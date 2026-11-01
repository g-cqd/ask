internal import AskAgentCore

/// A `tasks` call (ADR-0141): `changes`, a `read`, or both; each change only with the fields its `op` takes.
public struct TaskRequest: Decodable, Sendable {
    // @dl:accept -- the tasks and the ideas are two lists of one store (ADR-0141): their reads, inputs, tools and records share a shape over different fields
    let changes: [TaskEdit]?
    let read: TaskQuery?

    public init(from decoder: any Decoder) throws {
        let call = try ListCall.decode(decoder, TaskEditInput.self, TaskReadInput.self)
        changes = call.changes?.map(\.edit)
        read = call.read?.query
    }
}
