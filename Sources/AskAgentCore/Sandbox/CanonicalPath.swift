internal import Darwin
internal import Foundation

/// Paths made canonical before any sandbox decision (ADR-0035).
///
/// A rule about `~/.config/ask` means nothing if `~/work/link/../x` or a symlink or a differently cased spelling
/// reaches the same file. So every path is resolved the way the kernel would, and only then compared.
public enum CanonicalPath {
    /// The most dangling links followed while resolving one path, the kernel's own limit. A loop of links that exist
    /// ends first at the kernel's `ELOOP`, which `realpath` reports; this only bounds the iteration if that ever
    /// fails to happen, and no test can tell the two apart.
    static let maximumLinks = 32

    /// The canonical form of `path`: absolute, symbolic links resolved, no `.` or `..`.
    ///
    /// - A path that does not exist yet (a file about to be written) is the canonical form of its deepest existing
    ///   directory followed by the names that do not exist.
    /// - A dangling symbolic link is followed to where it points, because writing through it creates that file.
    /// - `..` after a name that does not exist cannot be resolved the way the kernel would (it fails), so it is
    ///   refused rather than guessed at.
    /// - Returns: nil when the path cannot be resolved: it contains a NUL, loops, or names something unreadable.
    public static func of(_ path: String, relativeTo directory: String) -> String? {
        guard !path.contains("\0"), !directory.contains("\0") else { return nil }
        var pending = path.hasPrefix("/") ? path : directory + "/" + path
        var followed = 0
        while true {
            let parts = pending.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
            // The longest prefix that exists, found by dropping names from the end.
            var existing = parts.count
            var resolved: String?
            while true {
                let prefix = "/" + parts[0 ..< existing].joined(separator: "/")
                var buffer = [CChar](repeating: 0, count: Int(PATH_MAX) + 1)
                if realpath(prefix, &buffer) != nil {
                    resolved = decode(buffer)
                    break
                }
                guard errno == ENOENT, existing > 0 else { return nil }
                existing -= 1
            }
            guard let base = resolved else { return nil }
            let rest = Array(parts[existing...])
            if rest.isEmpty { return base }
            // The first name that does not exist: a dangling link is followed, a missing name is not.
            let first = base == "/" ? "/" + rest[0] : base + "/" + rest[0]
            var info = stat()
            if lstat(first, &info) == 0, info.st_mode & S_IFMT == S_IFLNK {
                followed += 1
                guard followed <= maximumLinks, let target = linkTarget(first) else { return nil }
                let head = target.hasPrefix("/") ? target : base + "/" + target
                pending = ([head] + rest.dropFirst()).joined(separator: "/")
                continue
            }
            // Names that do not exist cannot be `..`, and `.` adds nothing.
            guard !rest.contains("..") else { return nil }
            let tail = rest.filter { $0 != "." }
            return tail.isEmpty ? base : (base == "/" ? "" : base) + "/" + tail.joined(separator: "/")
        }
    }

    private static func linkTarget(_ path: String) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX) + 1)
        let length = readlink(path, &buffer, Int(PATH_MAX))
        guard length > 0 else { return nil }
        return decode(Array(buffer[0 ..< length]))
    }

    /// The text of a C string held in `buffer`, up to its first NUL.
    private static func decode(_ buffer: [CChar]) -> String {
        String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}
