internal import Foundation

/// The parts of a git config file `modelScopes` reads (roadmap 0094): remote URLs, and `user.email` and `user.name`.
///
/// Read as git writes it: `[section "subsection"]` headers, `key = value` lines, `#` and `;` comments, quoted values, and
/// `include.path` and `includeIf "gitdir:…"` files read where they stand. A file that cannot be read is empty: a scope that cannot
/// see a fact does not match on it.
struct GitConfigFile: Sendable, Equatable {
    var remotes: [String] = []
    var email: String?
    var name: String?

    /// Where the file is read for: the repository's git directory, which `includeIf "gitdir:"` tests, and the home folder.
    struct Context: Sendable {
        var gitDirectory: String?
        var home: String
    }

    /// The file at `path`, empty when there is none; `depth` is how many includes led here, at most 10 as for git.
    static func read(_ path: String, context: Context, depth: Int = 0) -> GitConfigFile {
        guard depth <= 10, let data = FileManager.default.contents(atPath: path) else { return GitConfigFile() }
        var file = GitConfigFile()
        var section = ""
        for raw in String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") {
                section = header(line)
                continue
            }
            guard let equals = line.firstIndex(of: "=") else { continue }
            let key = line[..<equals].trimmingCharacters(in: .whitespaces).lowercased()
            let value = Self.value(line[line.index(after: equals)...])
            switch (section, key) {
                case (let name, "url") where name.hasPrefix("remote "): file.remotes.append(value)
                case ("user", "email"): file.email = value
                case ("user", "name"): file.name = value
                case (let name, "path") where name == "include" || applies(name, from: path, context: context):
                    let included = resolved(value, from: path, home: context.home)
                    file.merge(read(included, context: context, depth: depth + 1))
                default: break
            }
        }
        return file
    }

    /// `other`'s values over these, its remotes after them: what reading it at this point of the file gives.
    mutating func merge(_ other: GitConfigFile) {
        remotes += other.remotes
        email = other.email ?? email
        name = other.name ?? name
    }

    /// Whether `section` is an `includeIf "gitdir:…"` (or `gitdir/i:`) whose pattern holds the repository's git directory. Other
    /// conditions (`onbranch:`, `hasconfig:`) are not followed.
    private static func applies(_ section: String, from path: String, context: Context) -> Bool {
        guard section.hasPrefix("includeif "), let gitDirectory = context.gitDirectory else { return false }
        let condition = section.dropFirst("includeif ".count)
        guard let colon = condition.firstIndex(of: ":"), ["gitdir", "gitdir/i"].contains(condition[..<colon]) else {
            return false
        }
        var pattern = String(condition[condition.index(after: colon)...])
        if pattern.hasPrefix("~/") || pattern.hasPrefix("./") {
            pattern = resolved(pattern, from: path, home: context.home)
        } else if !pattern.hasPrefix("/") {
            pattern = "*/" + pattern
        }
        if pattern.hasSuffix("/") { pattern += "*" }
        return ScopeGlob(pattern).matches(gitDirectory)
    }

    /// An include's path: `~/` is the home folder, and a relative path is beside the file that names it.
    private static func resolved(_ value: String, from path: String, home: String) -> String {
        if value.hasPrefix("~/") { return home + value.dropFirst() }
        if value.hasPrefix("/") { return value }
        return ((path as NSString).deletingLastPathComponent as NSString).appendingPathComponent(value)
    }

    /// `[remote "origin"]` as `remote origin`; the section name is lowercased, the subsection kept.
    private static func header(_ line: String) -> String {
        let inside = line.dropFirst().prefix { $0 != "]" }
        let parts = inside.split(separator: " ", maxSplits: 1)
        let name = parts.first.map { $0.lowercased() } ?? ""
        guard parts.count == 2 else { return name }
        return name + " " + parts[1].trimmingCharacters(in: .whitespaces).trimmingCharacters(in: ["\""])
    }

    /// A value without its comment, its quotes and the spaces around it.
    private static func value(_ text: Substring) -> String {
        var result = ""
        var quoted = false
        for character in text {
            if character == "\"" {
                quoted.toggle()
            } else if !quoted, character == "#" || character == ";" {
                break
            } else {
                result.append(character)
            }
        }
        return result.trimmingCharacters(in: .whitespaces)
    }
}
