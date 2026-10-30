/// The `approvals` section of the person's own configuration file (roadmap 0134): which tool calls ask before they run.
public struct ApprovalsSection: Sendable, Equatable, CustomStringConvertible {
    /// What a call no list names does.
    public enum Mode: String, Sendable, CaseIterable { case ask, allow }

    /// What an "always" answer may write back to the configuration from inside ask: anything, only narrowing, or nothing. No answer
    /// writes the configuration yet, so this is read and kept for that answer.
    public enum Scope: String, Sendable, CaseIterable {
        case anything
        case narrowingOnly = "narrowing-only"
        case none
    }

    /// The keys a file may set under `approvals`.
    public static let keys = ["default", "allow", "ask", "scope"]

    public var defaultMode: Mode?
    /// Tool names, or `mcp__server__*` patterns, that run without asking.
    public var allow: [String]?
    /// Tool names, or patterns, that always ask, read-only ones included.
    public var ask: [String]?
    public var scope: Scope?

    public init(defaultMode: Mode? = nil, allow: [String]? = nil, ask: [String]? = nil, scope: Scope? = nil) {
        self.defaultMode = defaultMode
        self.allow = allow
        self.ask = ask
        self.scope = scope
    }

    public var description: String {
        let parts = [
            defaultMode.map { "default \($0.rawValue)" }, allow.map { "allow " + $0.joined(separator: ", ") },
            ask.map { "ask " + $0.joined(separator: ", ") }, scope.map { "scope \($0.rawValue)" }
        ]
        let shown = parts.compactMap(\.self)
        return shown.isEmpty ? "defaults" : shown.joined(separator: "; ")
    }
}
