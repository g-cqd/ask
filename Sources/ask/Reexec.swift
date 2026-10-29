internal import Darwin

/// Replaces this process with another program, keeping its terminal and the environment it was launched with (ADR-0033).
enum Reexec {
    /// Runs `path` with `arguments` (the first is the program's own name) in place of this process.
    ///
    /// The signal mask is cleared first, for the reason given in the body.
    ///
    /// Every descriptor other than standard input, output and error is marked close-on-exec first, whoever opened
    /// it: a descriptor that survived would keep its `flock`, and the new process would find the session it is
    /// about to resume locked by the one it replaced.
    /// - Returns: only on failure, with the errno. On success the process is already the new program.
    static func replaceProcess(with path: String, arguments: [String]) -> Int32 {
        // The calling thread is a Swift concurrency worker, which has SIGWINCH, SIGINT, SIGTERM and most other signals blocked. `execve`
        // gives its mask to the new program's first thread and, through it, to every thread that program makes, so a reloaded ask
        // could not be resized or terminated by a signal (roadmap 0132). A new program starts with nothing blocked.
        var unblocked = sigset_t()
        sigemptyset(&unblocked)
        pthread_sigmask(SIG_SETMASK, &unblocked, nil)
        for descriptor in 3 ..< Swift.max(3, getdtablesize()) { _ = fcntl(descriptor, F_SETFD, FD_CLOEXEC) }
        var pointers: [UnsafeMutablePointer<CChar>?] = arguments.map { strdup($0) }
        pointers.append(nil)
        defer { for pointer in pointers { free(pointer) } }
        // The launch environment, not the process's own: its credentials may have been blanked since (ADR-0113).
        var environment: [UnsafeMutablePointer<CChar>?] = LaunchEnvironment.values.map {
            strdup("\($0.key)=\($0.value)")
        }
        environment.append(nil)
        defer { for pointer in environment { free(pointer) } }
        execve(path, &pointers, &environment)
        return errno
    }
}
