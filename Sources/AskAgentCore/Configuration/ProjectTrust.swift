internal import AemiJSON
internal import CryptoKit
internal import Foundation

/// Which project configuration files the user has trusted (ADR-0031).
///
/// A project's `.ask/config.json` is text from a repository, which anyone may have written. It counts only
/// after the user runs `ask trust` in that project, and only for the exact bytes they trusted: trust is kept
/// as the file's path and SHA-256, as `direnv allow` keeps it, so a `git pull` that changes the file untrusts
/// it until the user looks again.
public struct ProjectTrust: Sendable, Equatable {
    /// What the store says about a project's file.
    public enum Standing: Sendable, Equatable {
        case trusted
        /// Never trusted.
        case unknown
        /// Trusted once, but the file has changed since.
        case changed
    }

    private var entries: [String: String]

    /// A store with nothing trusted.
    public init() { entries = [:] }

    /// The SHA-256 of `bytes`, in lowercase hex.
    public static func digest(_ bytes: [UInt8]) -> String {
        SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }

    /// Whether the file at `path` with these `bytes` is trusted.
    public func standing(of path: String, bytes: [UInt8]) -> Standing {
        guard let known = entries[path] else { return .unknown }
        return known == Self.digest(bytes) ? .trusted : .changed
    }

    /// Trusts `path` as it is now.
    public mutating func trust(_ path: String, bytes: [UInt8]) { entries[path] = Self.digest(bytes) }

    /// Forgets `path`. Returns whether it was trusted.
    @discardableResult
    public mutating func untrust(_ path: String) -> Bool { entries.removeValue(forKey: path) != nil }

    /// The trusted paths, sorted.
    public var paths: [String] { entries.keys.sorted() }

    // MARK: - The file

    /// The store at `path`: empty when there is none. A store that exists but cannot be read or parsed is an
    /// error, not an empty store, so a corrupted file cannot silently untrust or, worse, hide why.
    /// - Throws: ``ConfigurationError``.
    public static func load(_ path: String) throws(ConfigurationError) -> ProjectTrust {
        guard let bytes = try ConfigurationFileReader.read(path) else { return ProjectTrust() }
        do {
            var trust = ProjectTrust()
            trust.entries = try AemiJSON.JSONDecoder().decode([String: String].self, from: bytes)
            return trust
        } catch {
            throw .invalid(path: path, line: nil, column: nil, reason: "not a trust store: \(error)")
        }
    }

    /// Writes the store to `path`, owner-only, replacing it atomically, in a directory made owner-only.
    /// - Throws: ``ConfigurationError/unreadable(path:errno:)`` carrying the errno of whatever failed.
    public func save(to path: String) throws(ConfigurationError) {
        let directory = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(
            atPath: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var encoder = AemiJSON.JSONEncoder()
        encoder.prettyPrinted = true
        encoder.options.keyOrder = .sorted
        guard let data = try? encoder.encode(entries) else {
            throw .invalid(path: path, line: nil, column: nil, reason: "cannot encode")
        }
        let temporary = path + ".tmp"
        guard FileManager.default.createFile(atPath: temporary, contents: data, attributes: [.posixPermissions: 0o600])
        else {
            throw .unreadable(path: temporary, errno: errno)
        }
        guard rename(temporary, path) == 0 else {
            let failure = errno
            _ = unlink(temporary)
            throw .unreadable(path: path, errno: failure)
        }
    }
}
