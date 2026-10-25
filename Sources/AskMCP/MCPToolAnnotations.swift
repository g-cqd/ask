/// A server's hints about a tool. They are hints from the server, not facts ask can rely on: a server that calls its tool read-only
/// has said so, and nothing more.
// @dl:accept -- four optional hints and their initializer; any such record looks alike, as TokenUsage's does
public struct MCPToolAnnotations: Sendable, Equatable {
    /// The tool does not change anything.
    public var readOnly: Bool?
    /// The tool may destroy or overwrite.
    public var destructive: Bool?
    /// Calling it again with the same arguments changes nothing more.
    public var idempotent: Bool?
    /// The tool reaches outside the server, to the open world.
    public var openWorld: Bool?

    /// Annotations; every hint is unknown unless given.
    public init(readOnly: Bool? = nil, destructive: Bool? = nil, idempotent: Bool? = nil, openWorld: Bool? = nil) {
        self.readOnly = readOnly
        self.destructive = destructive
        self.idempotent = idempotent
        self.openWorld = openWorld
    }
}
