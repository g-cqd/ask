/// A server's resource named in a message as `@server:uri` (roadmap 0067).
public struct ResourceReference: Sendable, Hashable {
    public let server: String
    public let uri: String

    public init(server: String, uri: String) {
        self.server = server
        self.uri = uri
    }
}
