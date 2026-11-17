internal import System

/// A session file's bytes, kept open to read a line again when an entry whose payload was not kept is asked for it (roadmap 0238).
///
/// It opens the file on its own, not through the session's lock: the lock is an `flock` on an open file, shared by a duplicated
/// descriptor, and an entry copied out of the session (a search's snapshot, the screen's replay) would keep the session locked after
/// it closed. It reads at an offset, so no read moves another's place, and closes with the last entry that names it.
final class ColdSource: Sendable {
    private let descriptor: FileDescriptor

    /// The file at `path` opened for reading, or nil when it cannot be.
    init?(path: FilePath) {
        guard let descriptor = try? FileDescriptor.open(path, .readOnly) else { return nil }
        self.descriptor = descriptor
    }

    deinit { _ = try? descriptor.close() }

    /// The `length` bytes at `offset`, or nil when the file no longer has them.
    func read(offset: Int, length: Int) -> [UInt8]? {
        var bytes = [UInt8](repeating: 0, count: length)
        var done = 0
        while done < length {
            let count = bytes.withUnsafeMutableBytes { raw in
                try? descriptor.read(
                    fromAbsoluteOffset: Int64(offset + done),
                    into: UnsafeMutableRawBufferPointer(rebasing: raw[done...])
                )
            }
            guard let count, count > 0 else { return nil }
            done += count
        }
        return bytes
    }
}
