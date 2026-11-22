internal import Darwin
internal import Foundation

/// What an organisation puts on a managed machine for ask (roadmap 0130, ADR-0168): `requirements.json`, which no other layer changes,
/// and `defaults.json`, which a person may; each a `config.json`, each with drop-ins (`requirements.d/*.json`, `defaults.d/*.json`)
/// read in name order after it. A document is trusted only when it, and the folder holding it, belong to root and nobody else may
/// write them; otherwise, as when it does not parse, ask does not start.
public struct ManagedFiles: Sendable, Equatable {
    /// The two kinds of document.
    public enum Kind: String, Sendable, CaseIterable {
        /// Applied after every other layer: what the organisation requires.
        case requirements
        /// Applied before every other layer: where a person starts.
        case defaults
    }

    /// Where the system keeps them.
    #if os(macOS)
        public static let systemDirectory = "/Library/Application Support/ask"
    #else
        public static let systemDirectory = "/etc/ask"
    #endif

    /// The folder they are read from.
    public let directory: String
    /// Whom a document and its folder must belong to: root, unless a test names another.
    public let owner: UInt32

    public init(directory: String = Self.systemDirectory, owner: UInt32 = 0) {
        self.directory = directory
        self.owner = owner
    }

    /// The documents of `kind`, parsed, in the order they apply: the main file, then the drop-ins by name. Empty when the folder or
    /// the files are absent.
    /// - Throws: ``ConfigurationError/untrusted(path:reason:)`` for a document someone other than its owner could have written, and the
    ///   errors of ``ConfigurationFile/parse(_:path:isProject:)`` for one that is not a valid configuration.
    public func load(_ kind: Kind) throws(ConfigurationError) -> [(path: String, file: ConfigurationFile)] {
        var found: [(path: String, file: ConfigurationFile)] = []
        for path in paths(of: kind) {
            try check(path)
            guard let bytes = try ConfigurationFileReader.read(path) else { continue }
            found.append((path, try ConfigurationFile.parse(bytes, path: path)))
        }
        return found
    }

    /// The main document's path, if it exists, then the drop-ins' in name order.
    private func paths(of kind: Kind) -> [String] {
        let main = directory + "/" + kind.rawValue + ".json"
        let folder = directory + "/" + kind.rawValue + ".d"
        let dropIns = ((try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? [])
            .filter { $0.hasSuffix(".json") && !$0.hasPrefix(".") }.sorted().map { folder + "/" + $0 }
        return (FileManager.default.fileExists(atPath: main) ? [main] : []) + dropIns
    }

    /// Refuses `path` unless it, once its links are followed, and its folder belong to ``owner`` and only the owner may write them.
    private func check(_ path: String) throws(ConfigurationError) {
        guard let resolved = realpath(path, nil) else { throw .unreadable(path: path, errno: errno) }
        defer { free(resolved) }
        let file = String(cString: resolved)
        for (place, name) in [(file, "it"), ((file as NSString).deletingLastPathComponent, "its folder")] {
            var info = stat()
            guard lstat(place, &info) == 0 else { throw .unreadable(path: place, errno: errno) }
            if info.st_uid != owner {
                throw .untrusted(
                    path: path,
                    reason: "\(name) (\(place)) does not belong to \(owner == 0 ? "root" : "user \(owner)")"
                )
            }
            if info.st_mode & (S_IWGRP | S_IWOTH) != 0 {
                throw .untrusted(path: path, reason: "\(name) (\(place)) may be written by others than its owner")
            }
        }
    }
}
