/// The `sandbox` section of a configuration file: what the user adds to or lifts from ask's default protections
/// (ADR-0035), and the strict modes (roadmap 0042). Paths are absolute, or start with `~/` for the home directory.
public struct SandboxSection: Sendable, Equatable, CustomStringConvertible {
    /// Secret stores the user allows reading despite the default: `~/.aws` for the aws CLI, say. ask's own
    /// directories are never lifted by this, and only the user's own file may set it: a project that could widen
    /// the sandbox would defeat it.
    public var allowRead: [String]
    /// Further directories kept unreadable. This only narrows, so a project's file may set it too.
    public var denyRead: [String]
    /// Where commands and tools may write, one entry per layer that set it. They are intersected, so every layer
    /// narrows; empty means anywhere.
    public var write: [PathSetting]
    /// Where reading is allowed, one entry per layer that set it, intersected like `write`. Empty means the default:
    /// reading is a deny list. Anything else turns on the read allow-list (roadmap 0042).
    public var read: [PathSetting]
    /// How far the network reaches; nil for ask's default, anywhere. A layer can only lower it.
    public var network: SandboxPolicy.Network?

    /// A section with these settings.
    public init(
        allowRead: [String] = [], denyRead: [String] = [], write: [PathSetting] = [], read: [PathSetting] = [],
        network: SandboxPolicy.Network? = nil
    ) {
        self.allowRead = allowRead
        self.denyRead = denyRead
        self.write = write
        self.read = read
        self.network = network
    }

    /// Only the strict modes, which a session records: write and read scopes, and the network.
    public var strict: SandboxSection { SandboxSection(write: write, read: read, network: network) }

    public var isEmpty: Bool {
        allowRead.isEmpty && denyRead.isEmpty && write.isEmpty && read.isEmpty && network == nil
    }

    public var description: String {
        func scopes(_ settings: [PathSetting]) -> String {
            settings.count == 1 ? settings[0].description : "\(settings)"
        }
        return [
            allowRead.isEmpty ? nil : "allowRead \(allowRead)", denyRead.isEmpty ? nil : "denyRead \(denyRead)",
            write.isEmpty ? nil : "write " + scopes(write), read.isEmpty ? nil : "read " + scopes(read),
            network.map { "network \($0)" }
        ]
        .compactMap { $0 }.joined(separator: ", ")
    }

    /// `self` with a higher file layer's section applied: what may be read is replaced by the file that names it
    /// (only the user's can); everything else only narrows: denials accumulate, write scopes intersect, and the
    /// network takes the lower level.
    func layered(with section: SandboxSection) -> SandboxSection {
        SandboxSection(
            allowRead: section.allowRead.isEmpty ? allowRead : section.allowRead,
            denyRead: denyRead + section.denyRead.filter { !denyRead.contains($0) },
            // A scope already present narrows nothing more; keeping it once stops a resumed record from growing.
            write: write + section.write.filter { !write.contains($0) },
            read: read + section.read.filter { !read.contains($0) },
            network: Self.lower(network, section.network))
    }

    /// The lower of two levels, either of which may be unset.
    private static func lower(_ one: SandboxPolicy.Network?, _ other: SandboxPolicy.Network?) -> SandboxPolicy.Network?
    {
        guard let one else { return other }
        guard let other else { return one }
        return Swift.min(one, other)
    }

    /// Where writing is allowed: the intersection of every layer's scope, anywhere when none set one.
    public func writeScope(workspace: String, home: String) -> PathScope {
        write.reduce(PathScope.anywhere) { $0.intersecting($1.scope(workspace: workspace, home: home)) }
    }

    /// Where reading is allowed besides the system: `anywhere` unless some layer restricted it, else the intersection
    /// of the layers' scopes plus `always`, what a restricted run can always read (git's configuration, the
    /// toolchains, the user's `allowRead`).
    public func readScope(workspace: String, home: String, always: [String]) -> PathScope {
        let chosen = read.reduce(PathScope.anywhere) { $0.intersecting($1.scope(workspace: workspace, home: home)) }
        guard case .roots(let roots) = chosen else { return .anywhere }
        let extra = always.map { CanonicalPath.of($0, relativeTo: "/") ?? $0 }.filter { !roots.contains($0) }
        return .roots(roots + extra)
    }

    /// `path` with a leading `~` replaced by `home`.
    public static func expand(_ path: String, home: String) -> String {
        if path == "~" { return home }
        return path.hasPrefix("~/") ? home + String(path.dropFirst()) : path
    }
}
