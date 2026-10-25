/// One block of a tool's result.
public enum MCPContent: Sendable, Equatable {
    case text(String)
    case image(mimeType: String, base64: String)
    case audio(mimeType: String, base64: String)
    /// A pointer to something the server has, which this client has not read.
    case resourceLink(uri: String, name: String?, mimeType: String?)
    /// Something the server put in the result itself. `text` is nil for binary content.
    case resource(uri: String, mimeType: String?, text: String?)
    /// A block of a type this client does not know; only its name is kept.
    case unknown(type: String)
}
