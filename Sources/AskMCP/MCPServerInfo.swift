/// What a server said about itself when the connection started.
public struct MCPServerInfo: Sendable, Equatable {
    /// The protocol version both sides now speak.
    public let protocolVersion: String
    /// The server's name, for logs and listings.
    public let name: String
    /// A name for people, when it has one.
    public let title: String?
    /// The server's own version.
    public let version: String
    /// Text the server wants its model to read: what the server is for and how to use it. Not trusted: it is the server's words.
    public let instructions: String?
    /// Whether it has tools at all.
    public let supportsTools: Bool
    /// Whether it says its tools may change while connected, and will say so (``MCPEvent/toolsChanged``).
    public let toolsMayChange: Bool

    /// What a server said.
    public init(
        protocolVersion: String, name: String, title: String?, version: String, instructions: String?,
        supportsTools: Bool, toolsMayChange: Bool
    ) {
        self.protocolVersion = protocolVersion
        self.name = name
        self.title = title
        self.version = version
        self.instructions = instructions
        self.supportsTools = supportsTools
        self.toolsMayChange = toolsMayChange
    }
}
