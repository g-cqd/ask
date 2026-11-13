public import AemiSearch
internal import Foundation

/// Search over every plain session on this machine (t209, the owner's choices of 2026-11-12): an AemiSearch index kept beside the
/// sessions, brought up to date at every compaction and before a search, reading only what each session gained since (a byte offset
/// per file). Encrypted sessions are left out here: their index is to be kept beside them, under their key.
public actor SessionSearch {
    /// The state root's: `<root>/sessions` is read, `<root>/search` kept.
    public static let shared = SessionSearch(root: SessionDirectory.stateRoot())

    let root: String
    var index: SearchIndex?
    /// By session path: the bytes of it already indexed.
    var progress: [String: Int] = [:]

    public init(root: String) { self.root = root }

    var sessionsDirectory: String { root + "/sessions" }
    var searchDirectory: String { root + "/search" }

    /// Indexes what every plain session gained since the last update, and saves the index when anything was added.
    @discardableResult
    public func update() -> Int {
        let index = loaded()
        var added = 0
        for (path, project) in Self.sessionFiles(in: sessionsDirectory) {
            added += indexNewLines(of: path, project: project, into: index)
        }
        if added > 0 { save() }
        return added
    }

    /// The best hits for `query`, after an update.
    public func search(_ query: SearchQuery) -> [SearchHit] {
        update()
        return loaded().search(query)
    }

    /// How many documents the index holds.
    public var count: Int { loaded().count }

    /// Indexes the complete lines of `path` after its recorded offset; returns how many documents were added.
    private func indexNewLines(of path: String, project: String, into index: SearchIndex) -> Int {
        let start = progress[path] ?? 0
        guard let handle = FileHandle(forReadingAtPath: path) else { return 0 }
        defer { try? handle.close() }
        guard (try? handle.seekToEnd()).map({ Int($0) > start }) == true else { return 0 }
        try? handle.seek(toOffset: UInt64(start))
        guard let data = try? handle.readToEnd(), !data.isEmpty else { return 0 }
        let bytes = Array(data)
        if start == 0, !bytes.starts(with: Array(#"{"type":"session""#.utf8)) {
            progress[path] = bytes.count  // Encrypted or foreign: not read here.
            return 0
        }
        guard let lastNewline = bytes.lastIndex(of: 0x0A) else { return 0 }
        let session = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        let time = Int64(Date().timeIntervalSince1970)
        var added = 0
        for line in bytes[...lastNewline].split(separator: 0x0A) {
            for document in SessionSearchDocuments.documents(
                fromLine: line,
                session: session,
                project: project,
                time: time
            ) {
                index.add(document)
                added += 1
            }
        }
        progress[path] = start + lastNewline + 1
        return added
    }

    /// Every session file under `directory`, with its project's folder name.
    static func sessionFiles(in directory: String) -> [(path: String, project: String)] {
        let manager = FileManager.default
        let projects = (try? manager.contentsOfDirectory(atPath: directory)) ?? []
        return projects.sorted()
            .flatMap { project in
                ((try? manager.contentsOfDirectory(atPath: directory + "/" + project)) ?? []).sorted()
                    .filter { $0.hasSuffix(".jsonl") }
                    .map { (directory + "/" + project + "/" + $0, project) }
            }
    }
}
