/// Which new build of ask a change to its executable brought (ADR-0033).
///
/// The screen's one `FileChangeSignal` watches the executable's path with the configuration files (aemi ADR 0016): a
/// linker writes a new file and swaps it in, and the watcher follows the path. Each report is a reason to look again;
/// a new identity is reported only when the file at the path differs from the last one reported. A link raises several
/// events as it writes, so a consumer treats the first new build as "a build appeared" and not as "the build is
/// finished": the self-check at reload time decides that.
public struct BinaryWatcher: Sendable {
    /// The executable's path.
    public let path: String
    private var last: BinaryIdentity

    /// Looks for builds after `identity`, the one running.
    public init(since identity: BinaryIdentity) {
        path = identity.path
        last = identity
    }

    /// The build at the path now, when it differs from the last one reported; nil otherwise, or when it cannot be
    /// examined. Call it once when the watch begins too: a build that landed before raised no event.
    public mutating func look() -> BinaryIdentity? {
        guard let now = BinaryIdentity(path: path), now != last else { return nil }
        last = now
        return now
    }
}
