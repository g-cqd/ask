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
    public var write: [WriteSetting]
    /// How far the network reaches; nil for ask's default, anywhere. A layer can only lower it.
    public var network: SandboxPolicy.Network?

    /// A section with these settings.
    public init(
        allowRead: [String] = [], denyRead: [String] = [], write: [WriteSetting] = [],
        network: SandboxPolicy.Network? = nil
    ) {
        self.allowRead = allowRead
        self.denyRead = denyRead
        self.write = write
        self.network = network
    }

    public var isEmpty: Bool { allowRead.isEmpty && denyRead.isEmpty && write.isEmpty && network == nil }

    public var description: String {
        let write = self.write.count == 1 ? self.write[0].description : "\(self.write)"
        return [
            allowRead.isEmpty ? nil : "allowRead \(allowRead)", denyRead.isEmpty ? nil : "denyRead \(denyRead)",
            self.write.isEmpty ? nil : "write " + write, network.map { "network \($0)" }
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
            write: write + section.write,
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

    /// `path` with a leading `~` replaced by `home`.
    public static func expand(_ path: String, home: String) -> String {
        if path == "~" { return home }
        return path.hasPrefix("~/") ? home + String(path.dropFirst()) : path
    }
}
