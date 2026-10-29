internal import System

/// Reads a session log from a file a chunk at a time and recovers it line by line, so opening a session holds one chunk and one line, not
/// the whole file (roadmap 0088 step 3).
///
/// A file read whole was one allocation the size of the file. Freed after the open, it stayed resident until malloc reclaimed it: 11.5 MiB
/// of the 53 MiB a 12 MB session showed once open. Lines are what ``SessionLog/recover(_:limits:)`` sees: split at line feeds, the last
/// one final unless the file ends with a line feed.
struct SessionLogReader {
    /// The bytes read per system call.
    let chunkBytes: Int

    init(chunkBytes: Int = 64 << 10) { self.chunkBytes = Swift.max(1, chunkBytes) }

    /// The session in the file behind `descriptor`, read from its start.
    /// - Throws: ``SessionFileError`` for a read that fails or an archive past `limits`, and what recovery cannot repair.
    func recover(
        _ descriptor: FileDescriptor, limits: SessionLog.Limits, images: SessionImageStore?
    ) throws(SessionFileError) -> RecoveredSession {
        let size = Int(try SessionFileIO.io(.read) { try descriptor.seek(offset: 0, from: .end) })
        guard size <= limits.maximumArchiveBytes else { throw .log(.archiveTooLarge(size)) }
        _ = try SessionFileIO.io(.read) { try descriptor.seek(offset: 0, from: .start) }
        var lines = Lines(recovery: SessionLogRecovery(limits: limits, images: images), limit: limits.maximumLineBytes)
        var chunk = [UInt8](repeating: 0, count: chunkBytes)
        var total = 0
        // Never past the size checked above: a file that grows while it is read is read as it was.
        while total < size {
            let wanted = Swift.min(chunkBytes, size - total)
            let count = try SessionFileIO.io(.read) {
                try chunk.withUnsafeMutableBytes { raw in
                    try descriptor.read(into: UnsafeMutableRawBufferPointer(rebasing: raw[..<wanted]))
                }
            }
            if count == 0 { break }  // The file shrank while being read; recover what was there.
            total += count
            do { try lines.feed(chunk[..<count]) } catch { throw .log(error) }
        }
        guard total > 0 else { return RecoveredSession(tree: SessionTree(), issues: [.missingHeader]) }
        do { try lines.finish() } catch { throw .log(error) }
        return lines.recovery.result
    }

    /// Splits chunks into lines for the recovery: a line inside one chunk is passed as a slice of it, and one that spans chunks is gathered,
    /// unless it is already too long, when it is dropped as it arrives.
    struct Lines {
        var recovery: SessionLogRecovery
        let limit: Int
        private var pending: [UInt8] = []
        private var pendingTooLong = false
        private var number = 1

        init(recovery: SessionLogRecovery, limit: Int) {
            self.recovery = recovery
            self.limit = limit
        }

        mutating func feed(_ chunk: ArraySlice<UInt8>) throws(SessionLogError) {
            var start = chunk.startIndex
            while let end = chunk[start...].firstIndex(of: 0x0A) {
                if pending.isEmpty, !pendingTooLong {
                    try recovery.consume(chunk[start ..< end], number: number, isFinal: false)
                } else {
                    gather(chunk[start ..< end])
                    try endPending(isFinal: false)
                }
                number += 1
                start = end + 1
            }
            gather(chunk[start...])
        }

        /// The last line, when the file does not end with a line feed.
        mutating func finish() throws(SessionLogError) {
            guard !pending.isEmpty || pendingTooLong else { return }
            try endPending(isFinal: true)
        }

        private mutating func gather(_ bytes: ArraySlice<UInt8>) {
            guard !pendingTooLong, !bytes.isEmpty else { return }
            if pending.count + bytes.count > limit {
                pendingTooLong = true
                pending = []
            } else {
                pending += bytes
            }
        }

        private mutating func endPending(isFinal: Bool) throws(SessionLogError) {
            if pendingTooLong {
                recovery.skipTooLong(number: number)
            } else {
                try recovery.consume(pending[...], number: number, isFinal: isFinal)
            }
            pending.removeAll(keepingCapacity: true)
            pendingTooLong = false
        }
    }
}
