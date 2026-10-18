/// Bounds what a tool puts into the context, keeping the head and the tail around a marker.
///
/// An unbounded result does not fail loudly: it quietly fills the context window, and later turns degrade
/// for a reason nobody can see. The head usually says what ran and the tail how it ended, so both are kept.
/// Cuts fall on line boundaries, and inside one huge line on UTF-8 scalar boundaries. A combining mark can be
/// separated from its base there, but no encoded character is ever broken. Work is on bytes: one pass to
/// count lines, and walks from each end only as far as the budgets reach.
public struct OutputCap: Sendable, Equatable {
    public var maximumLines: Int
    public var maximumBytes: Int

    /// A cap of `maximumLines` lines and `maximumBytes` UTF-8 bytes, each at least 2.
    public init(maximumLines: Int, maximumBytes: Int) {
        self.maximumLines = Swift.max(2, maximumLines)
        self.maximumBytes = Swift.max(2, maximumBytes)
    }

    /// 2,000 lines or 50 KiB, whichever comes first.
    public static let standard = OutputCap(maximumLines: 2_000, maximumBytes: 50 << 10)

    /// `text`, or its head and tail around an omission marker when it exceeds the cap.
    public func apply(_ text: String) -> String {
        let bytes = Array(text.utf8)
        var newlines = 0
        for byte in bytes where byte == .newline { newlines += 1 }
        guard newlines + 1 > maximumLines || bytes.count > maximumBytes else { return text }
        let head = headLines(bytes)
        let tail = tailLines(bytes)
        guard head.count > 0 || tail.count > 0 else { return scalarCut(bytes) }
        let omitted = newlines + 1 - head.count - tail.count
        var pieces: [String] = []
        if head.count > 0 { pieces.append(String(decoding: bytes[..<head.end], as: UTF8.self)) }
        pieces.append("[… \(omitted) lines omitted …]")
        if tail.count > 0 { pieces.append(String(decoding: bytes[tail.start...], as: UTF8.self)) }
        return pieces.joined(separator: "\n")
    }

    /// The leading whole lines within half of each budget: how many, and where they end. A scan stops where
    /// the byte budget does, so one huge line costs the budget, not its length.
    private func headLines(_ bytes: [UInt8]) -> (count: Int, end: Int) {
        var (count, end, position, used) = (0, 0, 0, 0)
        while count < (maximumLines + 1) / 2, position < bytes.count {
            let limit = Swift.min(bytes.count, position + maximumBytes / 2 - used)
            var lineEnd = position
            while lineEnd < limit, bytes[lineEnd] != .newline { lineEnd += 1 }
            // A scan cut short by the limit costs one byte more than remains, so this also refuses partial lines.
            guard used + lineEnd - position + 1 <= maximumBytes / 2 else { break }
            used += lineEnd - position + 1
            (count, end, position) = (count + 1, lineEnd, lineEnd + 1)
        }
        return (count, end)
    }

    /// The trailing whole lines within half of each budget. Head and tail each take at most half of either
    /// budget, and capping happens only when the text exceeds one, so they cannot overlap.
    private func tailLines(_ bytes: [UInt8]) -> (count: Int, start: Int) {
        var (count, start, end, used) = (0, bytes.count, bytes.count, 0)
        while count < maximumLines / 2 {
            let limit = Swift.max(0, end - (maximumBytes / 2 - used))
            var lineStart = end
            while lineStart > limit, bytes[lineStart - 1] != .newline { lineStart -= 1 }
            guard used + end - lineStart + 1 <= maximumBytes / 2 else { break }
            used += end - lineStart + 1
            (count, start) = (count + 1, lineStart)
            guard lineStart > 0 else { break }
            end = lineStart - 1
        }
        return (count, start)
    }

    /// For text whose lines are each too long to keep whole: a prefix and a suffix cut on scalar boundaries.
    private func scalarCut(_ bytes: [UInt8]) -> String {
        var prefixEnd = Swift.min(maximumBytes / 2, bytes.count)
        while prefixEnd > 0, prefixEnd < bytes.count, bytes[prefixEnd].isContinuation { prefixEnd -= 1 }
        var suffixStart = Swift.max(bytes.count - maximumBytes / 2, prefixEnd)
        while suffixStart < bytes.count, bytes[suffixStart].isContinuation { suffixStart += 1 }
        let omitted = suffixStart - prefixEnd
        return String(decoding: bytes[..<prefixEnd], as: UTF8.self) + "[… \(omitted) bytes omitted …]"
            + String(decoding: bytes[suffixStart...], as: UTF8.self)
    }
}

extension UInt8 {
    fileprivate static let newline: UInt8 = 0x0A
    /// A UTF-8 continuation byte, which never starts a scalar.
    fileprivate var isContinuation: Bool { self & 0xC0 == 0x80 }
}
