internal import Foundation
internal import Synchronization

/// The screen's own thread, as a task executor (note n18): the loop that applies keys, the wheel and the conversation's updates to the
/// screen runs here, at the highest quality of service, instead of on Swift's shared threads. On a machine under heavy contention a
/// wheel step waited there behind everything else, and a trackpad's burst took hundreds of milliseconds, up to more than a second, to
/// settle. The render thread and the input thread are already threads of their own at this quality of service (TerminalKit).
///
/// Only what prefers this executor runs here: the loop (`withTaskExecutorPreference`) and the structured work it awaits. A task the
/// loop starts with `Task {}`, which is how the conversation's work starts, does not inherit the preference, so it stays on the shared
/// threads (SE-0417).
final class ScreenExecutor: TaskExecutor, Sendable {
    private let jobs = Mutex<(queue: [UnownedJob], stopped: Bool)>(([], false))
    private let wake = DispatchSemaphore(value: 0)

    /// Starts the thread, named `name`.
    init(name: String = "ask.screen") {
        let thread = Thread { [self] in run() }
        thread.name = name
        thread.qualityOfService = .userInteractive
        thread.stackSize = 1 << 20
        thread.start()
    }

    func enqueue(_ job: consuming ExecutorJob) {
        let job = UnownedJob(job)
        let accepted = jobs.withLock { state -> Bool in
            guard !state.stopped else { return false }
            state.queue.append(job)
            return true
        }
        // After the screen closed, a late job still runs, on a thread of its own, so nothing waiting on it hangs.
        guard accepted else {
            Thread { job.runSynchronously(on: self.asUnownedTaskExecutor()) }.start()
            return
        }
        wake.signal()
    }

    /// Ends the thread once the jobs already queued have run.
    func stop() {
        jobs.withLock { $0.stopped = true }
        wake.signal()
    }

    private func run() {
        while true {
            wake.wait()
            let (batch, stopped) = jobs.withLock { state in
                defer { state.queue.removeAll(keepingCapacity: true) }
                return (state.queue, state.stopped)
            }
            for job in batch {
                // A pool per job: this thread lives as long as the screen (as TerminalKit's render thread does, e345a88).
                autoreleasepool { job.runSynchronously(on: asUnownedTaskExecutor()) }
            }
            if stopped, jobs.withLock({ $0.queue.isEmpty }) { return }
        }
    }
}
