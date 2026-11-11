internal import Dispatch
internal import Foundation
internal import Synchronization
internal import TerminalKitIO

/// Sends the tab's title (note n60), its progress and notifications (note n62) from a thread of its own, in the order asked: never from the screen's thread, which a terminal that
/// is slow to take a frame must not hold up (note n18), as the first title, sent right behind the first frame, did. The thread starts
/// with the first title and ends with ``finish(_:)``.
final class TabTitleWriter: Sendable {
    private struct Pending {
        var writes: [[UInt8]] = []
        var started = false
        var finished = false
    }

    private let pending = Mutex(Pending())
    private let wake = DispatchSemaphore(value: 0)
    private let done = DispatchSemaphore(value: 0)
    private let connection: any TerminalConnection

    init(connection: any TerminalConnection) {
        self.connection = connection
    }

    /// Writes `bytes` after what was asked before, and returns at once.
    func send(_ bytes: [UInt8]) {
        let starts = pending.withLock { state -> Bool in
            guard !state.finished else { return false }
            state.writes.append(bytes)
            defer { state.started = true }
            return !state.started
        }
        if starts {
            let thread = Thread { [self] in run() }
            thread.name = "ask.tab-title"
            thread.start()
        }
        wake.signal()
    }

    /// Writes `bytes` after what was asked before, and returns once all of it is written; the thread then ends. For the title given
    /// back on exit.
    func finish(_ bytes: [UInt8]) {
        send(bytes)
        let started = pending.withLock { state -> Bool in
            state.finished = true
            return state.started
        }
        guard started else { return }
        wake.signal()
        done.wait()
    }

    private func run() {
        while true {
            wake.wait()
            let (writes, finished) = pending.withLock { state in
                defer { state.writes.removeAll() }
                return (state.writes, state.finished)
            }
            for bytes in writes { try? connection.write(bytes) }
            if finished {
                done.signal()
                return
            }
        }
    }
}
