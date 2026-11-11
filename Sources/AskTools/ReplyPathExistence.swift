public import AskAgentCore
internal import Darwin
internal import Foundation
internal import Synchronization

/// Whether a relative path in a reply may be linked without inspecting a protected file (roadmap 0215).
/// Symlinks are deliberately not followed: a rendered reference is not permission to resolve an arbitrary target.
public final class ReplyPathExistence: Sendable {
    private struct Cache {
        var workspace = ""
        var policy = SandboxPolicy.unrestricted
        /// Paths found, kept until the policy changes: a file since removed says so on the click.
        var found: Set<String> = []
        /// When each path was last not found: asked again once that is older than ``missingFor``.
        var missing: [String: ContinuousClock.Instant] = [:]
    }
    private let cache = Mutex(Cache())

    private let now: @Sendable () -> ContinuousClock.Instant

    /// - Parameter now: the time, for the age of a "not there" answer; a test passes its own.
    public init(now: @escaping @Sendable () -> ContinuousClock.Instant = { .now }) { self.now = now }

    /// How long "not there" is believed. A reply is laid out again on every streamed delta, so the answer must be kept; but the model
    /// names a file it is about to write, and that file must be found once it is there.
    static let missingFor = Duration.seconds(2)
    private static let limit = 4_096

    /// Whether `path` may be linked. Answers are kept for this conversation, and all forgotten when the policy or the workspace changes.
    public func exists(_ path: String, in workspace: String, policy: SandboxPolicy) -> Bool {
        let time = now()
        return cache.withLock { cache in
            if cache.workspace != workspace || cache.policy != policy {
                cache = Cache(workspace: workspace, policy: policy)
            }
            if cache.found.contains(path) { return true }
            if let asked = cache.missing[path], time - asked < Self.missingFor { return false }
            let result = Self.check(path, in: workspace, policy: policy)
            if cache.found.count + cache.missing.count >= Self.limit {
                cache.found.removeAll(keepingCapacity: true)
                cache.missing.removeAll(keepingCapacity: true)
            }
            if result {
                cache.missing[path] = nil
                cache.found.insert(path)
            } else {
                cache.missing[path] = time
            }
            return result
        }
    }

    /// Checks an absolute candidate beneath the caller's workspace under its current read policy. The workspace itself is
    /// caller-owned, not model text; only its canonical form is resolved. Candidate components are walked without following links.
    private static func check(_ path: String, in workspace: String, policy: SandboxPolicy) -> Bool {
        guard workspace.hasPrefix("/"), path.hasPrefix(workspace + "/"), !path.contains("\0") else { return false }
        let parts = path.dropFirst(workspace.count + 1).split(separator: "/", omittingEmptySubsequences: false)
        guard let leaf = parts.last, parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }),
            let root = CanonicalPath.of(workspace, relativeTo: "/")
        else { return false }
        let candidate = root + "/" + parts.joined(separator: "/")
        guard readable(root, policy: policy), readable(candidate, policy: policy) else { return false }
        // No candidate realpath/stat before the policy decision. O_NOFOLLOW is checked by the kernel for each component;
        // a renamed or replaced component cannot make the next open follow an unchecked symbolic link.
        var directory = open(root, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard directory >= 0 else { return false }
        defer { close(directory) }
        var prefix = root
        for part in parts.dropLast() {
            prefix += "/" + part
            guard readable(prefix, policy: policy) else { return false }
            let next = openat(directory, String(part), O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard next >= 0 else { return false }
            close(directory)
            directory = next
        }
        var info = stat()
        guard fstatat(directory, String(leaf), &info, AT_SYMLINK_NOFOLLOW) == 0 else { return false }
        return info.st_mode & S_IFMT != S_IFLNK
    }

    /// The candidate has no symlinks or dot components; policy matching itself performs no filesystem access.
    private static func readable(_ path: String, policy: SandboxPolicy) -> Bool {
        guard !policy.denyRead.contains(where: { $0.matches(path) }) else { return false }
        return policy.read.contains(path)
            || SandboxPolicy.systemReadRoots.contains { SandboxRule($0, .subpath).matches(path) }
    }
}
