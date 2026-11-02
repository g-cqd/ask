/// One of a server's resources, as its listing names it (roadmap 0067).
public struct MCPResource: Sendable, Equatable {
    public let uri: String
    public let name: String
    public let title: String?
    public let description: String?
    public let mimeType: String?

    public init(uri: String, name: String, title: String?, description: String?, mimeType: String?) {
        self.uri = uri
        self.name = name
        self.title = title
        self.description = description
        self.mimeType = mimeType
    }
}
