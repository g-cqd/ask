/// The `sandbox` section of a configuration file: what the user adds to or lifts from ask's default protections
/// (ADR-0035). Paths are absolute, or start with `~/` for the home directory.
public struct SandboxSection: Sendable, Equatable, CustomStringConvertible {
    /// Secret stores the user allows reading despite the default: `~/.aws` for the aws CLI, say. ask's own
    /// directories are never lifted by this, and only the user's own file may set it: a project that could widen
    /// the sandbox would defeat it.
    public var allowRead: [String]
    /// Further directories kept unreadable. This only narrows, so a project's file may set it too.
    public var denyRead: [String]

    /// A section with these lists.
    public init(allowRead: [String] = [], denyRead: [String] = []) {
        self.allowRead = allowRead
        self.denyRead = denyRead
    }

    public var isEmpty: Bool { allowRead.isEmpty && denyRead.isEmpty }

    public var description: String {
        [allowRead.isEmpty ? nil : "allowRead \(allowRead)", denyRead.isEmpty ? nil : "denyRead \(denyRead)"]
            .compactMap { $0 }.joined(separator: ", ")
    }

    /// `path` with a leading `~` replaced by `home`.
    public static func expand(_ path: String, home: String) -> String {
        if path == "~" { return home }
        return path.hasPrefix("~/") ? home + String(path.dropFirst()) : path
    }
}
