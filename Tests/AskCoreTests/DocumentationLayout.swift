internal import Foundation

/// Reads the shape of the repository's own documentation.
///
/// The rules this type exists to police are rules about writing, not about running: a journal that
/// nobody reads to the end, and a roadmap whose entries have grown into multi-item essays, both
/// fail silently. A silent failure is the one kind of documentation defect worth a test.
enum DocumentationLayout {
    /// The most lines a single diary file may hold before it rolls over to a new file.
    ///
    /// A diary is written, not read. Past this length nobody scrolls to the bottom to find out what
    /// happened last, so the ceiling is enforced here rather than left to good intentions.
    static let maximumDiaryLines = 256

    /// The most lines the white paper may hold.
    ///
    /// It is a core document of principles, not a log. Every probe that lands in the diary tempts
    /// someone to append it here as well, and a few dozen rows of history bury the principles that
    /// are the only reason anyone opens the file. The cap makes "is this a principle?" a mechanical
    /// question instead of a matter of restraint.
    static let maximumWhitePaperLines = 200

    /// The white paper's path.
    static func whitePaperURL() -> URL { repositoryRoot.appending(path: "docs/WHITE-PAPER.md") }

    /// The white paper's current line count.
    static func whitePaperLineCount() throws -> Int { try lineCount(of: whitePaperURL()) }

    /// A diary file that has reached `maximumDiaryLines`.
    struct OverlongDiaryFile: Sendable, Equatable {
        var url: URL
        var lines: Int
    }

    /// One roadmap entry, read from its own file.
    struct RoadmapEntry: Sendable, Equatable {
        var url: URL
        var text: String

        init(url: URL, text: String) {
            self.url = url
            self.text = text
        }

        /// The `status: pending` style field every entry declares.
        var declaresStatus: Bool {
            text.contains("status:")
        }

        /// Whether the file claims more than one entry.
        ///
        /// An entry is one unit of work, so the signals are the ones that actually mark one: a
        /// second top-level title, or a second `status:` field. Section headings deliberately do not
        /// count — an entry may legitimately have `## Done` and `## Still owed` sections, and treating
        /// those as extra entries punishes the file for being well organised.
        var holdsMultipleEntries: Bool {
            let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
            let titles = lines.filter { $0.hasPrefix("# ") }.count
            let statuses = lines.filter { $0.hasPrefix("status:") }.count
            return titles > 1 || statuses > 1
        }
    }

    // MARK: - Roots

    /// The repository root, found by walking up from this file to the directory holding `Package.swift`.
    static let repositoryRoot: URL = {
        var directory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // AskCoreTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // repository root
        precondition(
            FileManager.default.fileExists(atPath: directory.appending(path: "Package.swift").path),
            "could not locate the repository root above \(#filePath)"
        )
        return directory
    }()

    /// `docs/diary`.
    static func diaryDirectory() -> URL { repositoryRoot.appending(path: "docs/diary") }

    /// `docs/roadmap`.
    static func roadmapDirectory() -> URL { repositoryRoot.appending(path: "docs/roadmap") }

    /// `docs/adr`.
    static func adrDirectory() -> URL { repositoryRoot.appending(path: "docs/adr") }

    /// A scratch directory for fixtures the tests write and remove.
    static func fixtureDirectory() throws -> URL {
        let directory = repositoryRoot.appending(path: ".build/documentation-fixtures")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    // MARK: - Reading

    /// Whether `docs/diary` is present.
    static func diaryDirectoryExists() throws -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: diaryDirectory().path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    /// The diary files past the ceiling, longest first, so the worst offender leads the message.
    static func diaryFilesExceedingLines(_ limit: Int) throws -> [OverlongDiaryFile] {
        try filesExceedingLines(in: diaryDirectory(), limit: limit)
    }

    /// The Markdown files in `directory` that pass `limit` lines, longest first.
    static func filesExceedingLines(in directory: URL, limit: Int) throws -> [OverlongDiaryFile] {
        try markdownFiles(in: directory)
            .map { OverlongDiaryFile(url: $0, lines: try lineCount(of: $0)) }
            .filter { $0.lines > limit }
            .sorted { $0.lines > $1.lines }
    }

    /// Every roadmap entry file, in filename order.
    static func roadmapEntries() throws -> [RoadmapEntry] {
        try markdownFiles(in: roadmapDirectory())
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map { RoadmapEntry(url: $0, text: try String(contentsOf: $0, encoding: .utf8)) }
    }

    /// Every architecture decision record, in filename order.
    static func adrFiles() throws -> [URL] {
        try markdownFiles(in: adrDirectory()).sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    // MARK: - Lines

    /// The number of lines in a text file.
    ///
    /// An empty file has no lines at all, and a file ending in a newline does not gain a trailing
    /// empty line: both are counted the way a reader would count them.
    static func lineCount(of url: URL) throws -> Int {
        let contents = try String(contentsOf: url, encoding: .utf8)
        guard !contents.isEmpty else { return 0 }
        return contents.split(separator: "\n", omittingEmptySubsequences: false).count
            - (contents.hasSuffix("\n") ? 1 : 0)
    }

    // MARK: - Files

    /// The `.md` files directly inside `directory`, sorted by name. A missing directory yields no
    /// files rather than an error, so a repository that has not created the directory yet is not a
    /// failing build.
    private static func markdownFiles(in directory: URL) throws -> [URL] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasSuffix(".md") }
            .sorted()
            .map { directory.appending(path: $0) }
    }
}
