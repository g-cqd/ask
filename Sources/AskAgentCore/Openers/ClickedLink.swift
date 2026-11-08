/// A link the person clicked, as an opener reads it (roadmap 0216).
public struct ClickedLink: Sendable, Equatable {
    public var kind: OpenerRule.Kind
    /// The whole address: `file:///…`, `https://…`.
    public var url: String
    /// A file's or folder's path, decoded; nil for a web link.
    public var path: String?
    public var line: Int?
    public var column: Int?
    /// A web link's host; nil for a file.
    public var host: String?

    public init(
        kind: OpenerRule.Kind,
        url: String,
        path: String? = nil,
        line: Int? = nil,
        column: Int? = nil,
        host: String? = nil
    ) {
        self.kind = kind
        self.url = url
        self.path = path
        self.line = line
        self.column = column
        self.host = host
    }
}
