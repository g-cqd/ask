/// One part of what reading a resource returned: text, or bytes as the server wrote them, in base64.
public struct MCPResourceContents: Sendable, Equatable {
    public enum Body: Sendable, Equatable {
        case text(String)
        case blob(base64: String)
    }

    public let uri: String
    public let mimeType: String?
    public let body: Body

    public init(uri: String, mimeType: String?, body: Body) {
        self.uri = uri
        self.mimeType = mimeType
        self.body = body
    }
}
