internal import Foundation

extension PickerRanking {
    /// The most matches a file query keeps. A keystroke cannot rank twenty thousand rows for the screen, and nobody scrolls past two hundred.
    static let fileLimit = 200

    /// The files that match `query`, best first, as indices into `files.paths`.
    ///
    /// Four groups, each in listing order: a path that starts with the query, then one whose last component does, then one whose last
    /// component contains it, then one whose path does. Case is ignored. An empty query lists the first files as they were listed.
    /// - Returns: the indices, and whether more matched than were kept.
    /// - Complexity: one pass over the lowercased paths, so O(total bytes), stopping early once the best group is full.
    static func rank(files: ProjectFiles, query: String) -> (indices: [Int], capped: Bool) {
        let needle = Array(query.lowercased().utf8)
        let count = files.paths.count
        guard !needle.isEmpty else { return (Array(0 ..< Swift.min(count, fileLimit)), count > fileLimit) }
        var groups: [[Int]] = [[], [], [], []]
        var more = false
        let bytes = files.lowered
        // One libc search over every path at once finds the paths that hold the query anywhere. A hit that runs over the end of a
        // path joins two paths and counts for neither. Only a path that holds the query is looked at again, to tell the groups apart.
        bytes.withUnsafeBytes { buffer in
            var position = 0
            var index = 0
            while position + needle.count <= buffer.count, let hit = locate(needle, in: buffer, from: position) {
                while files.starts[index + 1] <= hit { index += 1 }
                guard hit + needle.count <= files.starts[index + 1] else {
                    position = hit + 1
                    continue
                }
                let start = files.starts[index]
                let end = files.starts[index + 1]
                let base = files.baseStarts[index]
                let group: Int
                if found(needle, in: bytes, from: start, before: end, anchored: true) {
                    group = 0
                } else if found(needle, in: bytes, from: base, before: end, anchored: true) {
                    group = 1
                } else if found(needle, in: bytes, from: base, before: end, anchored: false) {
                    group = 2
                } else {
                    group = 3
                }
                groups[group].append(index)
                // The best group is full: nothing later can rank above what it holds.
                if groups[0].count >= fileLimit {
                    more = index + 1 < files.paths.count
                    break
                }
                position = end
            }
        }
        let all = groups.flatMap { $0 }
        return (Array(all.prefix(fileLimit)), more || all.count > fileLimit)
    }

    /// Where `needle` first occurs in `buffer` at or after `position`, by libc's search.
    private static func locate(_ needle: [UInt8], in buffer: UnsafeRawBufferPointer, from position: Int) -> Int? {
        needle.withUnsafeBytes { wanted in
            guard let base = buffer.baseAddress,
                let hit = memmem(base + position, buffer.count - position, wanted.baseAddress, wanted.count)
            else { return nil }
            return base.distance(to: UnsafeRawPointer(hit))
        }
    }

    /// Whether `needle` is what `bytes` holds at `start` (`anchored`), or occurs anywhere from `start` to `end`.
    private static func found(
        _ needle: [UInt8], in bytes: ContiguousArray<UInt8>, from start: Int, before end: Int, anchored: Bool
    ) -> Bool {
        let last = end - needle.count
        guard last >= start else { return false }
        var position = start
        while position <= (anchored ? start : last) {
            var offset = 0
            while offset < needle.count, bytes[position + offset] == needle[offset] { offset += 1 }
            if offset == needle.count { return true }
            position += 1
        }
        return false
    }
}
