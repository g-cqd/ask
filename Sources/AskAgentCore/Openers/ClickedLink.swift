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
                // `#L12C5` after the address is the place a click carries (the screen's `PathLinks.Link.target`), not part of it.
                let place = Self.place(url.fragment())
                let address = place == nil ? uri : String(uri[..<(uri.lastIndex(of: "#") ?? uri.endIndex)])
                self.init(
                    kind: isDirectory(path) ? .folder : .file,
                    url: address,
                    path: path,
                    line: place?.line,
                    column: place?.column
                )
            case "http", "https":
                guard let host = url.host(), !host.isEmpty else { return nil }
                self.init(kind: .web, url: uri, host: host)
            default: return nil
        }
    }

    /// `L12` or `L12C5` as a line and a column; nil for anything else.
    private static func place(_ fragment: String?) -> (line: Int, column: Int?)? {
        guard let fragment, fragment.hasPrefix("L") else { return nil }
        // The screen reads `#L12C5` too (PathLinks.Link); AskTUI may not import this target, so one reader waits on roadmap 0209.
        let parts = fragment.dropFirst().split(separator: "C", maxSplits: 1, omittingEmptySubsequences: false)
        func number(_ text: Substring) -> Int? {
            // @dl:accept -- the same small reader on both sides of a boundary the layering forbids crossing
            (1 ... 9).contains(text.count) && text.allSatisfy { $0.isASCII && $0.isNumber } ? Int(text) : nil
        }
        guard let first = parts.first, let line = number(first) else { return nil }
        guard parts.count == 2 else { return (line, nil) }
        guard let column = number(parts[1]) else { return nil }
        return (line, column)
    }
}
