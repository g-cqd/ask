internal import Darwin
internal import Foundation

/// What arrives on a descriptor, read on a thread of its own, blocking, as pieces of an `AsyncStream`: a socket's bytes, or a
/// pseudo-terminal's. The stream finishes at the end of input or on an error.
package enum DescriptorReader {
    /// The pieces read from `descriptor`, each at most `pieceSize` bytes; `finished` runs on the reading thread once it stops.
    package static func pieces(
        of descriptor: Int32,
        pieceSize: Int = 65_536,
        finished: @escaping @Sendable () -> Void = {}
    ) -> AsyncStream<[UInt8]> {
        let (stream, sink) = AsyncStream<[UInt8]>.makeStream()
        Thread.detachNewThread {
            var buffer = [UInt8](repeating: 0, count: pieceSize)
            while true {
                let count = buffer.withUnsafeMutableBytes { unsafe read(descriptor, $0.baseAddress, $0.count) }
                if count < 0, errno == EINTR { continue }
                guard count > 0 else { break }
                sink.yield(Array(buffer[..<count]))
            }
            sink.finish()
            finished()
        }
        return stream
    }

    /// Writes all of `bytes` to `descriptor`, through short writes and interruptions; false when a write fails.
    @discardableResult
    package static func writeAll(_ bytes: [UInt8], to descriptor: Int32) -> Bool {
        var offset = 0
        while offset < bytes.count {
            let written = bytes[offset...].withUnsafeBytes { unsafe write(descriptor, $0.baseAddress, $0.count) }
            if written < 0, errno == EINTR { continue }
            guard written > 0 else { return false }
            offset += written
        }
        return true
    }
}
