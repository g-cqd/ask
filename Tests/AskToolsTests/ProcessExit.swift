import Darwin

/// Waits for a process that is not our child to exit, with kqueue: an event, not a poll.
enum ProcessExit {
    struct Failed: Error {}

    static func observed(_ pid: pid_t) async throws -> Bool {
        let queue = kqueue()
        guard queue >= 0 else { throw Failed() }
        defer { close(queue) }
        var change = kevent(
            ident: UInt(pid), filter: Int16(EVFILT_PROC), flags: UInt16(EV_ADD | EV_ONESHOT), fflags: NOTE_EXIT,
            data: 0, udata: nil)
        var event = kevent()
        // Registering fails with ESRCH when the process is already gone, which is the answer.
        let registered = unsafe kevent(queue, &change, 1, nil, 0, nil)
        if registered < 0 { return errno == ESRCH }
        var deadline = timespec(tv_sec: 10, tv_nsec: 0)
        let count = unsafe kevent(queue, nil, 0, &event, 1, &deadline)
        return count == 1 && event.fflags & NOTE_EXIT != 0
    }
}
