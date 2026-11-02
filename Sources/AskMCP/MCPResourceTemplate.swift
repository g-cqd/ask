/// A pattern of resource URIs a server can read (RFC 6570, such as `apple-docs://doc/{+key}`), for the ones it does not list one by one.
public struct MCPResourceTemplate: Sendable, Equatable {
    public let uriTemplate: String
    public let name: String
    public let description: String?
    public let mimeType: String?

    public init(uriTemplate: String, name: String, description: String?, mimeType: String?) {
        self.uriTemplate = uriTemplate
        self.name = name
        self.description = description
        self.mimeType = mimeType
    }
}
