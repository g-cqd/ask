internal import AskAgentCore

/// The shape of a `tasks` or `ideas` call (ADR-0141): `changes`, a `read`, or both, and nothing else.
enum ListCall {
    static func decode<Entry: Decodable, Read: Decodable>(
        _ decoder: any Decoder,
        _ entry: Entry.Type,
        _ read: Read.Type
    ) throws -> (changes: [Entry]?, read: Read?) {
        let container = try decoder.container(keyedBy: RecordKey.self)
        try container.only(["changes", "read"], in: "the call", for: "a call")
        let changes = try ToolInputError.entries(container, Entry.self)
        let reading = try container.field("read", Read.self)
        guard changes != nil || reading != nil else { throw ToolInputError("the call: send changes, a read, or both.") }
        return (changes, reading)
    }
}
