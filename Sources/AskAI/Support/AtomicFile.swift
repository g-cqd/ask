internal import Darwin
public import Foundation

/// Replaces a file whole: a new owner-only file beside it, flushed, then renamed over it, and the folder flushed, so a crash leaves the
/// old bytes or the new ones and never a mixture or an empty file (ADR-0089). The folder must already exist: each caller makes it with the permissions it wants.
public enum AtomicFile {
    /// What went wrong, as the errno of the system call that failed.
    public struct Failure: Error, Equatable {
        public let code: Int32
    }

    /// Writes `bytes` to `url`.
    /// - Parameters:
    ///   - url: the file to replace or create.
    ///   - bytes: the whole new contents.
    ///   - flush: how a descriptor is made durable; only tests give one, to see when and to make it fail.
    /// - Throws: a `Failure` naming the errno; the old file is untouched and no temporary file is left.
    public static func replace(
        _ url: URL, with bytes: [UInt8], flush: (Int32) -> Int32 = FileFlush.barrier
    ) throws(Failure) {
        let temporary = url.deletingLastPathComponent()
            .appending(path: ".\(url.lastPathComponent)-\(UUID().uuidString).tmp")
        let descriptor = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw Failure(code: errno) }
        // The buffer belongs to `bytes`, which outlives this synchronous write.
        let written = bytes.withUnsafeBytes { unsafe Darwin.write(descriptor, $0.baseAddress, $0.count) }
        // Before the rename, so the new name never reaches the disk ahead of the bytes it names.
        let flushed = flush(descriptor)
        let flushFailure = errno
        close(descriptor)
        guard written == bytes.count, flushed == 0, rename(temporary.path, url.path) == 0 else {
            let failure = flushed != 0 ? flushFailure : errno
            unlink(temporary.path)
            throw Failure(code: failure)
        }
        try flushDirectory(url.deletingLastPathComponent(), flush)
    }

    /// After the rename, so the new name is on the disk before the caller is told it worked. The file is already in place and cannot be
    /// put back, so a failure here is reported and nothing is undone.
    private static func flushDirectory(_ directory: URL, _ flush: (Int32) -> Int32) throws(Failure) {
        let descriptor = open(directory.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard descriptor >= 0 else { throw Failure(code: errno) }
        let flushed = flush(descriptor)
        let failure = errno
        close(descriptor)
        guard flushed == 0 else { throw Failure(code: failure) }
    }
}
