/// A change to a server a lower configuration file defines (roadmap 0127): an `mcp` entry with no `command` and no `url`. It changes only
/// what is used of the server, never what runs or what it is given, so a project cannot point your server, and the secrets you gave it,
/// at a program of its own.
public struct MCPServerMask: Sendable, Equatable {
    /// The keys a mask may set.
    static let keys: Set<String> = ["enabled", "tools", "mode", "maxDirectTools"]

    /// The server it changes.
    public var name: String
    public var enabled: Bool?
    public var tools: [String]?
    public var mode: MCPServerSetting.Mode?
    public var maxDirectTools: Int?
    /// Keys it set that only a server's definition may (`args`, `env`, `cwd`, `headers`), refused when the file is validated.
    var overreach: [String] = []

    /// `server` with what this sets.
    func applied(to server: MCPServerSetting) -> MCPServerSetting {
        var changed = server
        if let enabled { changed.enabled = enabled }
        if let tools { changed.tools = tools }
        if let mode { changed.mode = mode }
        if let maxDirectTools { changed.maxDirectTools = maxDirectTools }
        return changed
    }

    /// What it changes, in words: `off, tools build`.
    var changes: String {
        [
            enabled.map { $0 ? "on" : "off" }, tools.map { "tools " + $0.joined(separator: ", ") },
            mode.map { "mode \($0.rawValue)" }, maxDirectTools.map { "maxDirectTools \($0)" }
        ]
        .compactMap { $0 }.joined(separator: ", ")
    }
}
