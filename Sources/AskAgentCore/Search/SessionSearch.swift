public import AemiSearch
internal import CryptoKit
internal import Foundation
internal import Synchronization

/// Search over the current session's whole history (t209; the owner, 2026-11-12: the current session only), what compaction folded
/// away included: an AemiSearch index of the session's entries, whatever the file's format, kept beside it as `<session>.search` and
/// brought up to date at every compaction and before a search. An encrypted session's index is sealed (AES-GCM) under a key derived
/// from the user key, never written in the clear; with no key open it stays in memory.
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
    /// How many of the session's entries the index holds (entries are only appended).
    var indexed = 0

    public init(sessionPath: String) { self.sessionPath = sessionPath }

    /// The search of the session at `path` is let go, its index out of memory: the next search of that session reads its file again.
    /// Called when a conversation leaves a session (roadmap 0230), so an index does not stay for the life of the process.
    public static func forget(session path: String) {
        open.withLock { $0[path] = nil }
    }

    /// What a session holds at one moment, for an update that must not keep the session itself (roadmap 0230): a background update
    /// from a snapshot leaves the session free to be closed, and its lock with it.
    public struct Snapshot: Sendable {
        let entries: [SessionEntry]
        let sealing: (encrypted: Bool, key: SymmetricKey?)

        public init(of session: SessionRecorder) {
            entries = session.tree.entries
            sealing = session.searchSealing
        }
    }

    /// Indexes the entries `session` gained since the last update and saves the index; returns how many documents were added.
    @discardableResult
    public func update(from session: SessionRecorder) -> Int { update(from: Snapshot(of: session)) }

    /// The same, from what the session held when `snapshot` was taken.
    @discardableResult
    public func update(from snapshot: Snapshot) -> Int {
        let sealing = snapshot.sealing
        let entries = snapshot.entries
        let index = loaded(key: sealing.key)
        if entries.count < indexed {
            // Not the history this index was built from: start again.
            self.index = SearchIndex()
            indexed = 0
        }
        let target = self.index ?? index
        let time = Int64(Date().timeIntervalSince1970)
        var added = 0
        for entry in entries[indexed...] {
            for document in SessionSearchDocuments.documents(of: entry, time: time) {
                target.add(document)
                added += 1
            }
        }
        let grew = entries.count > indexed
        indexed = entries.count
        if grew { save(encrypted: sealing.encrypted, key: sealing.key) }
        return added
    }

    /// The best hits for `query` in `session`, after an update.
    public func search(_ query: SearchQuery, in session: SessionRecorder) -> [SearchHit] {
        update(from: session)
        return (index ?? SearchIndex()).search(query)
    }
}
