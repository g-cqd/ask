internal import Foundation

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

    /// The link `uri` names, as a click on it reads it: a `file:` link by its decoded path, a folder when `isDirectory` says so, and an
    /// `http:` or `https:` link by its host. Nil for mail and any other scheme, which stay the system's.
    public init?(uri: String, isDirectory: (String) -> Bool) {
        guard let url = URL(string: uri), let scheme = url.scheme?.lowercased() else { return nil }
        switch scheme {
            case "file":
                let path = url.path(percentEncoded: false)
                guard !path.isEmpty else { return nil }
                self.init(kind: isDirectory(path) ? .folder : .file, url: uri, path: path)
            case "http", "https":
                guard let host = url.host(), !host.isEmpty else { return nil }
                self.init(kind: .web, url: uri, host: host)
            default: return nil
        }
    }
}
