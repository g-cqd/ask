public import AemiSearch
internal import Foundation
internal import Synchronization

/// Search over the current session's whole history (t209; the owner, 2026-11-12: the current session only), what compaction folded
/// away included: an AemiSearch index kept beside the session file (`<session>.search`), brought up to date at every compaction and
/// before a search, reading only what the file gained since. No other session is read. An encrypted session is not indexed yet: its
/// index is to be kept under its key.
public actor SessionSearch {
    private static let open = Mutex<[String: SessionSearch]>([:])

    /// The one search of the session at `path`, shared by the model's tool, `/search` and compaction.
    public static func of(session path: String) -> SessionSearch {
        open.withLock { opened in
            if let search = opened[path] { return search }
            let search = SessionSearch(sessionPath: path)
            opened[path] = search
            return search
        }
    }

    let sessionPath: String
    var index: SearchIndex?
    /// The bytes of the session already indexed.
    var offset = 0
    /// Whether the session is one this search cannot read (encrypted).
    public private(set) var unreadable = false

    public init(sessionPath: String) { self.sessionPath = sessionPath }

    /// Indexes what the session gained since the last update, and saves the index when anything was added.
    @discardableResult
    public func update() -> Int {
        let index = loaded()
        let added = indexNewLines(into: index)
        if added > 0 { save() }
        return added
    }

    /// The best hits for `query` in this session, after an update.
    public func search(_ query: SearchQuery) -> [SearchHit] {
        update()
        return loaded().search(query)
    }

    /// Indexes the complete lines after the recorded offset; returns how many documents were added.
    private func indexNewLines(into index: SearchIndex) -> Int {
        guard let handle = FileHandle(forReadingAtPath: sessionPath) else { return 0 }
        defer { try? handle.close() }
        guard (try? handle.seekToEnd()).map({ Int($0) > offset }) == true else { return 0 }
        try? handle.seek(toOffset: UInt64(offset))
        guard let data = try? handle.readToEnd(), !data.isEmpty else { return 0 }
        let bytes = Array(data)
        if offset == 0, !bytes.starts(with: Array(#"{"type":"session""#.utf8)) {
            unreadable = true
            return 0
        }
        guard let lastNewline = bytes.lastIndex(of: 0x0A) else { return 0 }
        let session = ((sessionPath as NSString).lastPathComponent as NSString).deletingPathExtension
        let time = Int64(Date().timeIntervalSince1970)
        var added = 0
        for line in bytes[...lastNewline].split(separator: 0x0A) {
            for document in SessionSearchDocuments.documents(fromLine: line, session: session, project: "", time: time)
            {
                index.add(document)
                added += 1
            }
        }
        offset += lastNewline + 1
        return added
    }
}
