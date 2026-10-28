internal import Foundation

/// Makes lines from bytes, however they arrive: one stdio message is one line (ADR-0096).
///
/// A line is complete at its newline; a carriage return before it is dropped and an empty line is not a message. Newlines are found with
/// `memchr` in the new bytes only, so a megabyte that arrives in many chunks costs a megabyte and not its square, and a chunk that holds whole
/// lines while nothing is pending is cut straight into them, copied once (roadmap 0114). A line that grows past the limit without ending is
/// a stream that has gone wrong (a server printing something that is not messages), and everything after is refused.
struct LineSplitter {
    private var pending: [UInt8] = []
    private let maximumLineBytes: Int
    /// Whether a line outgrew the limit.
    private(set) var overflowed = false

    /// A splitter that accepts lines of at most `maximumLineBytes` bytes.
    init(maximumLineBytes: Int) { self.maximumLineBytes = maximumLineBytes }

    /// Takes `bytes` and returns the lines they completed.
    mutating func feed(_ bytes: [UInt8]) -> [[UInt8]] {
        bytes.withUnsafeBytes { feed($0) }
    }

    /// Takes the bytes in `buffer`, which are not kept, and returns the lines they completed.
    mutating func feed(_ buffer: UnsafeRawBufferPointer) -> [[UInt8]] {
        guard !overflowed, let base = buffer.baseAddress, !buffer.isEmpty else { return [] }
        var lines: [[UInt8]] = []
        var start = 0
        while start < buffer.count, let found = memchr(base + start, 0x0A, buffer.count - start) {
            let newline = found - UnsafeMutableRawPointer(mutating: base)
            if pending.isEmpty {
                append(UnsafeRawBufferPointer(rebasing: buffer[start ..< newline]), to: &lines)
            } else {
                pending.append(contentsOf: UnsafeRawBufferPointer(rebasing: buffer[start ..< newline]))
                pending.withUnsafeBytes { append($0, to: &lines) }
                pending.removeAll(keepingCapacity: true)
            }
            start = newline + 1
        }
        if start < buffer.count { pending.append(contentsOf: UnsafeRawBufferPointer(rebasing: buffer[start...])) }
        if pending.count > maximumLineBytes {
            overflowed = true
            pending = []
        }
        return lines
    }

    /// Adds `line` to `lines` without a carriage return at its end; an empty line is not added.
    private func append(_ line: UnsafeRawBufferPointer, to lines: inout [[UInt8]]) {
        var count = line.count
        if count > 0, line[count - 1] == 0x0D { count -= 1 }
        if count > 0 { lines.append(Array(UnsafeRawBufferPointer(rebasing: line[0 ..< count]))) }
    }
}
