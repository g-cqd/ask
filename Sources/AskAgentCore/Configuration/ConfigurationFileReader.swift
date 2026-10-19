internal import Darwin

/// Reads a small configuration file with the system calls themselves, so a failure carries its real errno.
///
/// `FileManager.contents(atPath:)` returns nil for a missing file and for an unreadable one alike, and an
/// unreadable configuration file that is quietly treated as absent would change ask's behaviour with no
/// explanation. A file larger than ``maximumBytes`` is refused without being read: no configuration is that
/// large, and one that is, is not a configuration.
enum ConfigurationFileReader {
    static let maximumBytes = 1 << 20

    /// The bytes of the file at `path`, or nil when there is no such file.
    /// - Throws: ``ConfigurationError/unreadable(path:errno:)``, or ``ConfigurationError/outOfRange(path:key:reason:)``
    ///   for a file over ``maximumBytes``.
    static func read(_ path: String) throws(ConfigurationError) -> [UInt8]? {
        let descriptor = open(path, O_RDONLY | O_CLOEXEC)
        guard descriptor >= 0 else {
            if errno == ENOENT || errno == ENOTDIR { return nil }
            throw .unreadable(path: path, errno: errno)
        }
        defer { close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0 else { throw .unreadable(path: path, errno: errno) }
        guard info.st_size <= maximumBytes else {
            throw .outOfRange(path: path, key: "file", reason: "is \(info.st_size) bytes; the limit is \(maximumBytes)")
        }
        var bytes = [UInt8](repeating: 0, count: Int(info.st_size))
        var filled = 0
        while filled < bytes.count {
            let count = bytes.withUnsafeMutableBytes {
                Darwin.read(descriptor, $0.baseAddress! + filled, $0.count - filled)
            }
            if count < 0 { throw .unreadable(path: path, errno: errno) }
            if count == 0 { break }  // The file shrank while being read; parse what was there.
            filled += count
        }
        bytes.removeLast(bytes.count - filled)
        return bytes
    }
}
