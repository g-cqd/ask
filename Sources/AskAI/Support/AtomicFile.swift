internal import Darwin
internal import Foundation

/// Replaces a file whole: a new owner-only file beside it, flushed, then renamed over it, so a crash leaves the old bytes or the
/// new ones and never a mixture. The folder must already exist: each caller makes it with the permissions it wants.
enum AtomicFile {
    /// What went wrong, as the errno of the system call that failed.
    struct Failure: Error, Equatable {
        let code: Int32
    }

    /// Writes `bytes` to `url`.
    /// - Parameters:
    ///   - url: the file to replace or create.
    ///   - bytes: the whole new contents.
    /// - Throws: a `Failure` naming the errno; the old file is untouched and no temporary file is left.
    static func replace(_ url: URL, with bytes: [UInt8]) throws(Failure) {
        let temporary = url.deletingLastPathComponent()
            .appending(path: ".\(url.lastPathComponent)-\(UUID().uuidString).tmp")
        let descriptor = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw Failure(code: errno) }
        // The buffer belongs to `bytes`, which outlives this synchronous write.
        let written = bytes.withUnsafeBytes { unsafe Darwin.write(descriptor, $0.baseAddress, $0.count) }
        let flushed = fsync(descriptor)
        close(descriptor)
        guard written == bytes.count, flushed == 0, rename(temporary.path, url.path) == 0 else {
            let failure = errno
            unlink(temporary.path)
            throw Failure(code: failure)
        }
    }
}
