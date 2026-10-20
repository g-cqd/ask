internal import Foundation

/// The files a git configuration names that git must read: what an `[include]` or `[includeIf]` section's `path`
/// points to, and `core.excludesFile`. Git treats an unreadable include as fatal, so a read allow-list that left them
/// out would break every commit (diary 42). One level: an included file's own includes are not followed.
public enum GitConfigReads {
    /// The absolute paths `text` names. Relative paths are relative to `directory`, the including file's directory;
    /// `~/` is `home`. Section names and keys are case-insensitive; `#` and `;` start comments; values may be quoted.
    public static func paths(in text: String, directory: String, home: String) -> [String] {
        var section = ""
        var found: [String] = []
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("#") || line.hasPrefix(";") || line.isEmpty { continue }
            if line.hasPrefix("[") {
                let name = line.dropFirst().prefix { $0 != "]" && $0 != " " && $0 != "\"" }
                section = name.lowercased()
                continue
            }
            guard let equals = line.firstIndex(of: "=") else { continue }
            let key = line[..<equals].trimmingCharacters(in: .whitespaces).lowercased()
            let wanted =
                (key == "path" && (section == "include" || section == "includeif"))
                || (key == "excludesfile" && section == "core")
            guard wanted, let value = Self.value(line[line.index(after: equals)...]) else { continue }
            found.append(Self.absolute(value, directory: directory, home: home))
        }
        return found
    }

    /// A value without its quotes or a trailing comment.
    private static func value(_ text: Substring) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("\"") {
            let inner = trimmed.dropFirst().prefix { $0 != "\"" }
            return inner.isEmpty ? nil : String(inner)
        }
        let bare = trimmed.prefix { $0 != "#" && $0 != ";" }.trimmingCharacters(in: .whitespaces)
        return bare.isEmpty ? nil : bare
    }

    private static func absolute(_ path: String, directory: String, home: String) -> String {
        if path == "~" || path.hasPrefix("~/") { return SandboxSection.expand(path, home: home) }
        if path.hasPrefix("/") { return path }
        return (directory.hasSuffix("/") ? directory : directory + "/") + path
    }
}
