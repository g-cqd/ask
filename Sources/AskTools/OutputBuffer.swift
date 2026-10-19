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

    /// The kept bytes in order, head then tail, without the omission marker: for searching.
    var kept: [UInt8] { head + tail[tailStart...] + tail[..<tailStart] }

    /// The kept text, with a marker where bytes were omitted.
    var text: String {
        let ordered = Array(tail[tailStart...] + tail[..<tailStart])
        let start = String(decoding: head, as: UTF8.self)
        guard omitted > 0 else { return start + String(decoding: ordered, as: UTF8.self) }
        return start + "\n[… \(omitted) bytes omitted …]\n" + String(decoding: ordered, as: UTF8.self)
    }
}
