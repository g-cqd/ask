internal import Darwin

/// Replaces this process with another program, keeping its terminal and environment (ADR-0033).
enum Reexec {
    /// Runs `path` with `arguments` (the first is the program's own name) in place of this process.
    ///
    /// Every descriptor other than standard input, output and error is marked close-on-exec first, whoever opened
    /// it: a descriptor that survived would keep its `flock`, and the new process would find the session it is
    /// about to resume locked by the one it replaced.
    /// - Returns: only on failure, with the errno. On success the process is already the new program.
    static func replaceProcess(with path: String, arguments: [String]) -> Int32 {
        for descriptor in 3 ..< Swift.max(3, getdtablesize()) { _ = fcntl(descriptor, F_SETFD, FD_CLOEXEC) }
        var pointers: [UnsafeMutablePointer<CChar>?] = arguments.map { strdup($0) }
        pointers.append(nil)
        defer { for pointer in pointers { free(pointer) } }
        execv(path, &pointers)
        return errno
    }
}
