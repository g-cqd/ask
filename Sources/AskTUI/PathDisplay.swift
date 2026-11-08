internal import TerminalKitMarkdown

/// Paths in replies and reasoning (roadmap 0215, note n31). An absolute or `~/` path is shown relative to the project when it is inside it,
/// or from a common folder at most ``ancestors`` levels above it (`../other/b.md`), else as written, and links to its file. A relative
/// path is linked only when ``exists`` says it is there, and is asked about only when it stays inside the project, so nothing outside is
/// looked for on the disk. A `:line` or `:line:column` after a path is kept on what is shown and left out of the link. What is shown
/// stands over what was written, so a copy takes the path as the model wrote it (TerminalKit's `MarkdownPath`).
struct PathDisplay: Sendable, Equatable {
    /// The project, absolute.
    var workspace: String
    var home: String
    /// How many folders above the project a common folder may be; nil for no limit.
    var ancestors: Int?
    /// Whether paths are shown short (`ui.paths` `short`) or as written.
    var shortens = true
    /// Whether the absolute path inside the project names something on the disk.
    var exists: @Sendable (String) -> Bool

    static func == (lhs: Self, rhs: Self) -> Bool {
        (lhs.workspace, lhs.home, lhs.ancestors, lhs.shortens) == (rhs.workspace, rhs.home, rhs.ancestors, rhs.shortens)
    }

    /// The paths in a run of prose, each with the text it shows and the file it opens.
    func paths(in text: String) -> [MarkdownPath] {
        Self.words(in: Array(text.utf8))
            .compactMap { word in
                guard let (shown, absolute) = resolve(word.path), let uri = PathLinks.uri(absolute, home: home) else {
                    return nil
                }
                return MarkdownPath(bytes: word.bytes, shown: shown + word.location, uri: uri)
            }
    }

    /// What `path` shows, and the absolute path it names; nil when it is not one to link.
    private func resolve(_ path: String) -> (shown: String, absolute: String)? {
        if path.hasPrefix("/") || path.hasPrefix("~/") {
            let absolute = Self.normalized(path.hasPrefix("~/") ? home + path.dropFirst(1) : path)
            return (shortens ? short(absolute) ?? path : path, absolute)
        }
        let absolute = Self.normalized(workspace + "/" + path)
        // A relative path is asked about only inside the project: `../secret` is never looked for.
        guard absolute.hasPrefix(workspace + "/"), exists(absolute) else { return nil }
        return (path, absolute)
    }

    /// `absolute` relative to the project, or from a common folder within the limit above it; nil beyond.
    private func short(_ absolute: String) -> String? {
        let base = workspace.split(separator: "/")
        let parts = absolute.split(separator: "/")
        let common = zip(base, parts).prefix { $0 == $1 }.count
        let ups = base.count - common
        // With no limit the root itself is the common folder; with one, the paths share at least a folder.
        guard let limit = ancestors else { return Self.climbing(ups, parts[common...]) }
        guard common > 0, ups <= limit else { return nil }
        return Self.climbing(ups, parts[common...])
    }

    /// `rest`, reached by climbing `ups` folders: `../../rest`, or `.` for the project itself.
    private static func climbing(_ ups: Int, _ rest: ArraySlice<Substring>) -> String {
        let rest = rest.joined(separator: "/")
        if ups == 0 { return rest.isEmpty ? "." : rest }
        let climb = Array(repeating: "..", count: ups).joined(separator: "/")
        return rest.isEmpty ? climb : climb + "/" + rest
    }

    /// `path` without `.` and `..` components or doubled slashes, read as written: no link is followed.
    static func normalized(_ path: String) -> String {
        var parts: [Substring] = []
        for part in path.split(separator: "/") where part != "." {
            if part == ".." { _ = parts.popLast() } else { parts.append(part) }
        }
        return "/" + parts.joined(separator: "/")
    }
}
