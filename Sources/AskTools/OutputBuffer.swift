internal import AskAgentCore

/// The first and the last `keeping` bytes of a stream, with a count of what fell between, so memory stays
/// bounded however much a command prints.
struct OutputBuffer: Sendable {
    private let keeping: Int
    private var head: [UInt8] = []
    private var tail: [UInt8] = []
    private var tailStart = 0
    private(set) var omitted = 0

    /// An empty buffer keeping `keeping` bytes at each end.
    init(keeping: Int) { self.keeping = keeping }

    var isEmpty: Bool { head.isEmpty && omitted == 0 }

    mutating func append(_ bytes: [UInt8]) {
        // Keeping nothing keeps nothing: everything is counted as omitted, and the ring below is never indexed.
        guard keeping > 0 else {
            omitted += bytes.count
            return
        }
        var rest = bytes[...]
        if head.count < keeping {
            let taken = rest.prefix(keeping - head.count)
            head += taken
            rest = rest.dropFirst(taken.count)
        }
        for byte in rest {
            if tail.count < keeping {
                tail.append(byte)
            } else {
                tail[tailStart] = byte
                tailStart = (tailStart + 1) % keeping
                omitted += 1
            }
        }
    }

    /// The kept bytes in order, head then tail, without the omission marker. Where bytes were omitted the two are not adjacent in the
    /// stream, so this is for counting and comparing the ends, not for searching: use ``contains(_:)``.
    var kept: [UInt8] { head + orderedTail }

    private var orderedTail: [UInt8] { Array(tail[tailStart...] + tail[..<tailStart]) }

    /// Whether the stream the buffer holds contains `needle` as one run of bytes. Where nothing was omitted the head and the tail are
    /// the stream; where bytes were omitted they are two runs with a gap, and a text cannot span a gap it never crossed.
    /// - Parameter needle: the bytes to look for; empty is never found.
    /// - Returns: whether the stream holds those bytes in a row.
    func contains(_ needle: [UInt8]) -> Bool {
        guard !needle.isEmpty else { return false }
        if omitted == 0 { return kept.firstRange(of: needle) != nil }
        return head.firstRange(of: needle) != nil || orderedTail.firstRange(of: needle) != nil
    }

    /// The kept text, with a marker where bytes were omitted.
    ///
    /// Where nothing was omitted the head and the tail are the stream and are decoded as one. Where bytes were omitted each side is cut
    /// to a whole character, and the marker counts every byte the text does not show.
    var text: String {
        guard omitted > 0 else { return String(decoding: kept, as: UTF8.self) }
        let ordered = orderedTail
        let start = UTF8Cut.droppingPartialEnd(head[...])
        let end = UTF8Cut.droppingPartialStart(ordered[...])
        let shown = start.count + end.count
        let dropped = omitted + head.count + ordered.count - shown
        return String(decoding: start, as: UTF8.self) + "\n[… \(dropped) bytes omitted …]\n"
            + String(decoding: end, as: UTF8.self)
    }
}
