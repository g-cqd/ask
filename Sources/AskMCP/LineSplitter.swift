/// Makes lines from bytes, however they arrive: one stdio message is one line (ADR-0096).
///
/// A line is complete at its newline; a carriage return before it is dropped and an empty line is not a message. Only the new bytes
/// are searched, so a megabyte that arrives in many chunks costs a megabyte and not its square. A line that grows past the limit
/// without ending is a stream that has gone wrong (a server printing something that is not messages), and everything after is refused.
struct LineSplitter {
    private var pending: [UInt8] = []
    private let maximumLineBytes: Int
    /// Whether a line outgrew the limit.
    private(set) var overflowed = false

    /// A splitter that accepts lines of at most `maximumLineBytes` bytes.
    init(maximumLineBytes: Int) { self.maximumLineBytes = maximumLineBytes }

    /// Takes `bytes` and returns the lines they completed.
    mutating func feed(_ bytes: [UInt8]) -> [[UInt8]] {
        guard !overflowed else { return [] }
        var lines: [[UInt8]] = []
        var start = 0
        let searchedBefore = pending.count
        pending.append(contentsOf: bytes)
        var scan = searchedBefore
        while scan < pending.count {
            if pending[scan] == 0x0A {
                var end = scan
                if end > start, pending[end - 1] == 0x0D { end -= 1 }
                if end > start { lines.append(Array(pending[start ..< end])) }
                start = scan + 1
            }
            scan += 1
        }
        pending.removeSubrange(0 ..< start)
        if pending.count > maximumLineBytes {
            overflowed = true
            pending = []
        }
        return lines
    }
}
