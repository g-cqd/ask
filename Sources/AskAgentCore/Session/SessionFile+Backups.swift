internal import Darwin
internal import System

/// Keeping the file as it was, under a name that says why, before a rewrite replaces it (ADR-0013).
extension SessionFile {
    /// Hard-links the current file to the first free versioned or damaged backup. Nothing to keep if it is gone, and nothing more to
    /// do if an earlier attempt already linked this very file: a rewrite that failed to rename is tried again, and the same bytes
    /// must not be kept once for each try.
    func preserveOriginal(suffix base: String) throws(SessionFileError) {
        for attempt in 1 ... 1_000 {
            let suffix = attempt == 1 ? base : base + "-\(attempt)"
            if link(path.string, path.string + suffix) == 0 { return }
            switch errno {
                case EEXIST:
                    if Self.isSameFile(path.string, path.string + suffix) { return }
                    continue
                case ENOENT: return
                default: throw .io(.link, errno: errno)
            }
        }
        throw .io(.link, errno: EEXIST)
    }

    /// Whether two names are one file: the same device and inode.
    static func isSameFile(_ first: String, _ second: String) -> Bool {
        var one = stat()
        var other = stat()
        guard stat(first, &one) == 0, stat(second, &other) == 0 else { return false }
        return one.st_dev == other.st_dev && one.st_ino == other.st_ino
    }
}
