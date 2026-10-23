internal import Foundation

/// Where the Antigravity CLI is installed.
public enum AgyBinary {
    /// Overrides every other source.
    public static let environmentName = "AGY_BINARY"

    /// The names the program goes by: the installers alias the tarball's `antigravity` to `agy`.
    static let names = ["agy", "antigravity"]

    /// Absolute places searched after `$PATH`; a program started without a shell has no `$PATH` worth the name.
    static let knownPlaces = [
        "/opt/homebrew/bin/antigravity", "/opt/homebrew/bin/agy", "/usr/local/bin/agy", "/usr/local/bin/antigravity",
        "/usr/bin/antigravity", "/usr/bin/agy", "~/.local/bin/antigravity", "~/.local/bin/agy", "~/bin/agy"
    ]

    /// The `agy` binary, or nil when none is found.
    /// - Parameters:
    ///   - environment: the process environment.
    ///   - home: what `~` means.
    ///   - exists: whether a path is a file; injected so no test reads a real 190 MB binary.
    /// - Returns: the path, which for an override is not checked to exist; nil when nothing is found.
    public static func locate(environment: [String: String], home: String, exists: (String) -> Bool) -> String? {
        if let override = environment[environmentName]?.trimmingCharacters(in: .whitespaces), !override.isEmpty {
            return override
        }
        let directories = (environment["PATH"] ?? "").split(separator: ":", omittingEmptySubsequences: true)
        for name in names {
            for directory in directories where exists("\(directory)/\(name)") { return "\(directory)/\(name)" }
        }
        return knownPlaces.map { $0.hasPrefix("~/") ? home + $0.dropFirst(1) : $0 }.first(where: exists)
    }
}
