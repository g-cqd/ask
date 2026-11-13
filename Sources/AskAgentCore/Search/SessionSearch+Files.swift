internal import AemiSearch
internal import Foundation

/// Where the session index is kept: `<root>/search/index` (an AemiSearch snapshot) and `<root>/search/progress` (one `offset\tpath`
/// line per session), both the person's alone (0600, in a 0700 folder) and replaced atomically. A damaged snapshot is dropped and
/// rebuilt from the sessions.
extension SessionSearch {
    var indexPath: String { searchDirectory + "/index" }
    var progressPath: String { searchDirectory + "/progress" }

    /// The index, read from its file the first time.
    func loaded() -> SearchIndex {
        if let index { return index }
        let read = readSnapshot()
        index = read ?? SearchIndex()
        if read == nil { progress = [:] }
        return index ?? SearchIndex()
    }

    private func readSnapshot() -> SearchIndex? {
        guard let data = FileManager.default.contents(atPath: indexPath),
            let snapshot = try? SearchIndex(serialized: Array(data)),
            let lines = try? String(contentsOfFile: progressPath, encoding: .utf8)
        else { return nil }
        var read: [String: Int] = [:]
        for line in lines.split(separator: "\n") {
            let parts = line.split(separator: "\t", maxSplits: 1)
            guard parts.count == 2, let offset = Int(parts[0]) else { return nil }
            read[String(parts[1])] = offset
        }
        progress = read
        return snapshot
    }

    func save() {
        guard let index else { return }
        let manager = FileManager.default
        try? manager.createDirectory(
            atPath: searchDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let lines = progress.sorted { $0.key < $1.key }.map { "\($0.value)\t\($0.key)" }.joined(separator: "\n")
        write(Data(index.serialized()), to: indexPath)
        write(Data(lines.utf8), to: progressPath)
    }

    private func write(_ data: Data, to path: String) {
        let url = URL(fileURLWithPath: path)
        guard (try? data.write(to: url, options: [.atomic])) != nil else { return }
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
    }
}
