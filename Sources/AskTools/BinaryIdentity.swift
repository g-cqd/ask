internal import Darwin
public import Foundation

/// Which build of ask a file is: where it is, and the file's identity, size and modification time (ADR-0033).
///
/// A rebuilt executable is a new file: the linker writes a new inode (probed, `docs/research/self-development-and-
/// reload.md`), so a changed inode is a new build, and size and time catch an in-place write. Hashing the
/// 8 MB executable instead would cost milliseconds of cold start for a question the file system already answers.
public struct BinaryIdentity: Sendable, Equatable {
    /// The executable's real path, with symlinks resolved.
    public let path: String
    let device: Int64
    let inode: UInt64
    public let size: Int64
    let seconds: Int64
    let nanoseconds: Int64

    /// The file at `path`, or nil when it cannot be examined.
    public init?(path: String) {
        guard let real = realpath(path, nil) else { return nil }
        defer { free(real) }
        let resolved = String(cString: real)
        var info = stat()
        guard stat(resolved, &info) == 0 else { return nil }
        self.path = resolved
        device = Int64(info.st_dev)
        inode = UInt64(info.st_ino)
        size = Int64(info.st_size)
        seconds = Int64(info.st_mtimespec.tv_sec)
        nanoseconds = Int64(info.st_mtimespec.tv_nsec)
    }

    /// The running executable, examined now. Cheap: one `stat`.
    public static func running() -> BinaryIdentity? {
        var length: UInt32 = 0
        _ = _NSGetExecutablePath(nil, &length)
        var buffer = [CChar](repeating: 0, count: Int(length))
        guard _NSGetExecutablePath(&buffer, &length) == 0 else { return nil }
        return BinaryIdentity(
            path: String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self))
    }

    /// The same file, unchanged: path, file identity, size and modification time all agree.
    public static func == (left: BinaryIdentity, right: BinaryIdentity) -> Bool {
        left.path == right.path && left.device == right.device && left.inode == right.inode
            && left.size == right.size && left.seconds == right.seconds && left.nanoseconds == right.nanoseconds
    }

    /// When the file was last written, as a date.
    public var modified: Date { Date(timeIntervalSince1970: Double(seconds) + Double(nanoseconds) / 1e9) }

    /// For people: the build's time and size, such as `built 14:02:11, 8.1 MB`.
    public var summary: String {
        let time = modified.formatted(
            .dateTime.hour(.twoDigits(amPM: .omitted)).minute().second().locale(Locale(identifier: "en_GB")))
        return "built \(time), \(String(format: "%.1f", Double(size) / 1_000_000)) MB"
    }
}
