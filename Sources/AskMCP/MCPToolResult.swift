/// What a tool call returned.
public struct MCPToolResult: Sendable, Equatable {
    /// The blocks, in order.
    public let content: [MCPContent]
    /// The structured result as the server sent it, when it sent one.
    public let structuredContent: [UInt8]?
    /// The tool ran and failed, and `content` says how. A failure of the call itself is an ``MCPError`` instead.
    public let isError: Bool

    /// A result.
    public init(content: [MCPContent], structuredContent: [UInt8]?, isError: Bool) {
        self.content = content
        self.structuredContent = structuredContent
        self.isError = isError
    }
}
