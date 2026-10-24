internal import Darwin
internal import Synchronization

/// Stops the jobs' process groups if ask is killed in a way it cannot see (ADR-0079).
///
/// ask stops every job on each exit it can observe: the end of `-p`, closing the screen, SIGTERM and SIGINT. A SIGKILL, or a crash, is
/// not one of them, and a job runs in its own session, so it would outlive ask for good. This holds one end of a pipe whose other end is
/// the standard input of a small `/bin/sh` that outlives ask. ask writes `+PID` when a job starts and `-PID` when it ends; when the
/// pipe closes for any reason, which the kernel does when ask dies, the shell stops each group still listed: SIGTERM, two seconds, SIGKILL.
///
/// Nothing is started until the first job. The pipe is made at once, so a job's registration never waits, and the shell is started on
/// a thread of its own: the kernel keeps what was written until it reads. If the shell cannot start, ask runs as it did before, and
/// ``protection`` says so.
final class JobWatchdog: Sendable {
    /// Whether the jobs are covered.
    enum Protection: Sendable, Equatable {
        /// No job has started yet, so there is no process.
        case idle
        /// The pipe is open and the shell is being started.
        case starting
        /// The shell, by process id, is watching the pipe.
        case running(pid_t)
        /// The shell could not be started, or the pipe could not be made, or was lost.
        case unavailable
    }

    /// Resumed, once the lock is let go, when ``protection`` becomes what they wait for.
    private typealias Resumptions = [CheckedContinuation<Void, Never>]

    private struct State {
        /// Ask's end of the pipe.
        var descriptor: Int32?
        private(set) var protection = Protection.idle
        var watching = Set<pid_t>()
        /// Set once the pipe has been closed, so nothing opens it again.
        var closed = false
        var waiters: [Int: (wanted: @Sendable (Protection) -> Bool, continuation: CheckedContinuation<Void, Never>)] =
            [:]
        var nextWaiter = 0

        /// Changes ``protection``.
        /// - Returns: the waiters this satisfies.
        mutating func set(_ new: Protection) -> Resumptions {
            protection = new
            let met = waiters.filter { $0.value.wanted(new) }
            for key in met.keys { waiters[key] = nil }
            return met.values.map(\.continuation)
        }
    }

    private let state = Mutex(State())
    private let shell: String

    /// A watchdog that has not started anything.
    /// - Parameter shell: the shell that is the watchdog process.
    init(shell: String = "/bin/sh") { self.shell = shell }

    deinit { state.withLock { Self.close(&$0) } }

    /// The process groups listed now.
    var watching: Set<pid_t> { state.withLock { $0.watching } }

    /// Whether, and by which process, the jobs are covered.
    var protection: Protection { state.withLock { $0.protection } }

    /// Lists a job's process group, which is its leader's id, so it is stopped if ask dies.
    /// - Parameter group: the process group.
    func watch(_ group: pid_t) {
        let met: Resumptions = state.withLock { state in
            guard !state.closed else { return [] }
            state.watching.insert(group)
            let opened = state.descriptor == nil ? open(&state) : []
            return opened + Self.send("+\(group)\n", &state)
        }
        for continuation in met { continuation.resume() }
    }

    /// Takes a group off the list: its job has ended, and a group id may be used again.
    /// - Parameter group: the process group.
    func release(_ group: pid_t) {
        let met: Resumptions = state.withLock { state in
            guard state.watching.remove(group) != nil else { return [] }
            return Self.send("-\(group)\n", &state)
        }
        for continuation in met { continuation.resume() }
    }

    /// Closes the pipe as the kernel does when ask dies, leaving every group listed. For tests.
    func simulateDeath() { state.withLock { Self.close(&$0) } }

    /// ask's end of the pipe while it is open. For tests, which look at how it is set up and for it in a job.
    func openDescriptorForTesting() -> Int32? { state.withLock { $0.descriptor } }

    /// Returns once ``protection`` is something `wanted` accepts: an event, not a poll, and not for ever, so that a test of a broken
    /// watchdog fails and does not hang. For tests.
    /// - Parameters:
    ///   - limit: the longest to wait.
    ///   - wanted: what the protection should have become.
    func waitForProtection(within limit: Duration = .seconds(10), _ wanted: @escaping @Sendable (Protection) -> Bool)
        async
    {
        await withCheckedContinuation { continuation in
            let registered: Int? = state.withLock { state in
                if wanted(state.protection) { return nil }
                state.nextWaiter += 1
                state.waiters[state.nextWaiter] = (wanted, continuation)
                return state.nextWaiter
            }
            guard let key = registered else { return continuation.resume() }
            // Holds the watchdog for no longer than it takes to look: a test of one let go must see it go.
            Task { [weak self] in
                try? await Task.sleep(for: limit)
                let late = self?.state.withLock { $0.waiters.removeValue(forKey: key)?.continuation }
                late?.resume()
            }
        }
    }

    // MARK: - The pipe

    /// Makes the pipe and starts the shell on a thread of its own.
    private func open(_ state: inout State) -> Resumptions {
        var ends: [Int32] = [-1, -1]
        guard pipe(&ends) == 0 else { return state.set(.unavailable) }
        for end in ends { _ = fcntl(end, F_SETFD, FD_CLOEXEC) }
        // A watchdog that is gone must not kill ask with SIGPIPE, or stop it by filling the pipe.
        _ = fcntl(ends[1], F_SETNOSIGPIPE, 1)
        _ = fcntl(ends[1], F_SETFL, fcntl(ends[1], F_GETFL) | O_NONBLOCK)
        state.descriptor = ends[1]
        let (shell, input) = (shell, ends[0])
        DetachedThread.start(stackBytes: 64 << 10) { [weak self] in
            let process = Self.spawn(shell: shell, input: input)
            self?.settle(process.map { .running($0) } ?? .unavailable) { $0 == .starting }
            // The shell is ask's child, so it is reaped when it ends, and it ends when the pipe closes. If it ends while ask still
            // holds the pipe, the jobs are no longer covered.
            guard let process else { return }
            var status: Int32 = 0
            while waitpid(process, &status, 0) < 0 && errno == EINTR {}
            self?.settle(.unavailable) { if case .running = $0 { true } else { false } }
        }
        return state.set(.starting)
    }

    /// Changes ``protection`` from another thread, if it is still what `current` accepts.
    private func settle(_ new: Protection, if current: (Protection) -> Bool) {
        let met: Resumptions = state.withLock { state in current(state.protection) ? state.set(new) : [] }
        for continuation in met { continuation.resume() }
    }

    private static func send(_ line: String, _ state: inout State) -> Resumptions {
        guard let descriptor = state.descriptor else { return [] }
        let bytes = Array(line.utf8)
        // One short write is atomic in a pipe; a full pipe means the shell is not reading, and ask does not wait for it.
        return unsafe write(descriptor, bytes, bytes.count) == bytes.count ? [] : state.set(.unavailable)
    }

    private static func close(_ state: inout State) {
        state.closed = true
        if let descriptor = state.descriptor { Darwin.close(descriptor) }
        state.descriptor = nil
    }
}
