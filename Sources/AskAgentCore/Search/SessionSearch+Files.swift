internal import AemiSearch
internal import Foundation

/// Where a session's index is kept: `<session>.search` (an AemiSearch snapshot) and `<session>.search-offset` (the bytes of the session
/// it holds), beside the session in its 0700 folder, each 0600 and replaced atomically. A damaged or missing one is rebuilt from the
/// session. Neither ends in `.jsonl`, so neither is taken for a session.
extension SessionSearch {
    var indexPath: String { sessionPath + ".search" }
    var offsetPath: String { sessionPath + ".search-offset" }

    /// The index, read from its file the first time.
    func loaded() -> SearchIndex {
        if let index { return index }
        let read = readSnapshot()
        let opened = read ?? SearchIndex()
        if read == nil { offset = 0 }
        index = opened
        return opened
    }

    private func readSnapshot() -> SearchIndex? {
        guard let data = FileManager.default.contents(atPath: indexPath),
            let snapshot = try? SearchIndex(serialized: Array(data)),
            let text = try? String(contentsOfFile: offsetPath, encoding: .utf8),
            let read = Int(text.trimmingCharacters(in: .whitespacesAndNewlines))
        else { return nil }
        offset = read
        return snapshot
    }

    func save() {
        guard let index else { return }
        write(Data(index.serialized()), to: indexPath)
        write(Data(String(offset).utf8), to: offsetPath)
    }

    private func write(_ data: Data, to path: String) {
        guard (try? data.write(to: URL(fileURLWithPath: path), options: [.atomic])) != nil else { return }
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
    }
}
