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

    var isEmpty: Bool { head.isEmpty }

    mutating func append(_ bytes: [UInt8]) {
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
    var text: String {
        let ordered = orderedTail
        let start = String(decoding: head, as: UTF8.self)
        guard omitted > 0 else { return start + String(decoding: ordered, as: UTF8.self) }
        return start + "\n[… \(omitted) bytes omitted …]\n" + String(decoding: ordered, as: UTF8.self)
    }
}
