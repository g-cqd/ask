/// One `openers.rules` entry (roadmap 0216): what links it matches, every criterion given having to hold, and the app or the command it
/// opens them with.
public struct OpenerRule: Sendable, Equatable {
    public enum Kind: String, Sendable, CaseIterable {
        case file, folder, web
    }

    public var kind: Kind?
    /// File extensions, without the dot, compared without case.
    public var extensions: [String]?
    /// A web link's host, compared without case; `github.com` also matches `www.github.com`.
    public var host: String?
    /// An AemiRegex over the link's target: a file's path, or a web link's whole address.
    public var pattern: String?
    /// The app: a name or a bundle identifier. A rule has an app or a command, never both.
    public var app: String?
    /// The command, as arguments, with `{path}`, `{line}`, `{column}` and `{url}` in them.
    public var command: [String]?

    public init(
        kind: Kind? = nil,
        extensions: [String]? = nil,
        host: String? = nil,
        pattern: String? = nil,
        app: String? = nil,
        command: [String]? = nil
    ) {
        self.kind = kind
        self.extensions = extensions
        self.host = host
        self.pattern = pattern
        self.app = app
        self.command = command
    }
}
