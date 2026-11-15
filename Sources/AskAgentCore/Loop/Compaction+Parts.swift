/// Cutting a conversation into parts that each fit a summary request (ADR-0155).
extension Compaction {
    /// Where the part of `entries` that starts at `start` ends: after the whole turns that hold at most `bytes` together, and after
    /// the first one whatever its size, so a part is never empty and a tool result is never parted from its call.
    static func partEnd(_ entries: [SessionEntry], from start: Int, holding bytes: Int) -> Int {
        var end = start
        var held = 0
        while end < entries.endIndex {
            var next = end + 1
            while next < entries.endIndex, !startsATurn(entries[next].payload) { next += 1 }
            let turn = size(of: entries[end ..< next])
            if end > start, held + turn > bytes { break }
            held += turn
            end = next
        }
        return end
    }

    /// What `entries` add to a request, in bytes.
    static func size(of entries: ArraySlice<SessionEntry>) -> Int {
        entries.reduce(0) { $0 + size($1.payload) }
    }
}
