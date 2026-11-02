internal import Darwin
internal import Foundation
internal import Synchronization

/// Stops a check's program at its deadline (roadmap 0188).
///
/// The wait is a thread of its own, sleeping in `poll` on a pipe: a task on the cooperative pool never woke under load, as the check
/// blocks a pool thread while it reads, so the command waited on its check. ``cancel()`` closes the pipe, which wakes the thread at once,
/// so a quick check leaves nothing waiting.
final class CheckWatchdog: Sendable {
    private let wake = Pipe()
    private let fired = Atomic<Bool>(false)

    /// Whether the deadline passed with the program still running, so it was stopped.
    var stopped: Bool { fired.load(ordering: .acquiring) }

    /// Starts waiting: `process` is stopped if it is still running after `deadline`; `ended` is told when the wait is over, for tests.
    init(_ process: Process, deadline: Duration, ended: @escaping @Sendable () -> Void = {}) {
        let (seconds, attoseconds) = deadline.components
        let milliseconds = Int32(clamping: seconds * 1000 + attoseconds / 1_000_000_000_000_000)
        let reading = wake.fileHandleForReading
        DetachedThread.start(stackBytes: 64 << 10) { [self] in
            var waiting = pollfd(fd: reading.fileDescriptor, events: Int16(POLLIN), revents: 0)
            let woken = unsafe poll(&waiting, 1, milliseconds)
            try? reading.close()
            defer { ended() }
            guard woken == 0, process.isRunning else { return }
            fired.store(true, ordering: .releasing)
            process.terminate()
        }
    }

    /// Ends the wait: the program ended on its own.
    func cancel() { try? wake.fileHandleForWriting.close() }
}
