internal import AemiSearch
internal import CryptoKit
internal import Foundation

/// The index's file, `<session>.search`, beside the session in its 0700 folder, 0600, replaced atomically: the count of entries it
/// holds (8 bytes, little-endian) and the AemiSearch snapshot; for an encrypted session that whole is sealed with AES-GCM, the file's
/// name authenticated. A file that does not read (damaged, sealed under another key, or clear for an encrypted session) is dropped
/// and the index built again from the entries. Its name does not end in `.jsonl`, so it is never taken for a session.
extension SessionSearch {
    var indexPath: String { sessionPath + ".search" }
    private var nameTag: Data { Data(("ask.search:" + (sessionPath as NSString).lastPathComponent).utf8) }

    /// The index, read from its file the first time.
    func loaded(key: SymmetricKey?) -> SearchIndex {
        if let index { return index }
        let read = readFile(key: key)
        indexed = read?.indexed ?? 0
        let opened = read?.index ?? SearchIndex()
        index = opened
        return opened
    }

    private func readFile(key: SymmetricKey?) -> (index: SearchIndex, indexed: Int)? {
        guard let data = FileManager.default.contents(atPath: indexPath) else { return nil }
        var plain = data
        if let key {
            guard let box = try? AES.GCM.SealedBox(combined: data),
                let opened = try? AES.GCM.open(box, using: key, authenticating: nameTag)
            else { return nil }
            plain = opened
        }
        let bytes = Array(plain)
        guard bytes.count > 8 else { return nil }
        var count = 0
        for offset in 0 ..< 8 { count |= Int(bytes[offset]) << (offset * 8) }
        guard count >= 0, let snapshot = try? SearchIndex(serialized: Array(bytes[8...])) else { return nil }
        return (snapshot, count)
    }

    /// Writes the index: sealed under `key` for an encrypted session, in the clear otherwise; an encrypted session with no key open
    /// writes nothing.
    func save(encrypted: Bool, key: SymmetricKey?) {
        guard let index, !encrypted || key != nil else { return }
        var bytes: [UInt8] = []
        for offset in 0 ..< 8 { bytes.append(UInt8(truncatingIfNeeded: indexed >> (offset * 8))) }
        bytes += index.serialized()
        var data = Data(bytes)
        if let key {
            guard let sealed = try? AES.GCM.seal(data, using: key, authenticating: nameTag).combined else { return }
            data = sealed
        }
        // try?: the index is a cache, built again from the session
        guard (try? data.write(to: URL(fileURLWithPath: indexPath), options: [.atomic])) != nil else { return }
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: indexPath)
    }
}
