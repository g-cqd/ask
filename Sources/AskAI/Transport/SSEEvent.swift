/// One dispatched server-sent event.
public struct SSEEvent: Sendable, Equatable {
    /// The `event:` field, or `message` when the event named none.
    public let name: String
    /// The `data:` lines, joined with line feeds.
    public let data: [UInt8]

    /// An event with this name and data.
    public init(name: String, data: [UInt8]) {
        self.name = name
        self.data = data
    }
}
