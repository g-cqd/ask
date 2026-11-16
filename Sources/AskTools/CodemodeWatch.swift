internal import Darwin
internal import Synchronization

/// A keeper's watch over the memory of a script's process, from outside it (ADR-0156). A Python script that makes one
/// allocation larger than its limit holds the interpreter's lock while it is filled, so the thread that watches from inside
/// sees it only once made: 3 GiB were taken that way. From outside it is seen as it grows, and the process is ended there.
final class CodemodeWatch: Sendable {
    /// How often the footprint is read, in microseconds: a script can take 10 MB a millisecond.
    private static let interval: UInt32 = 2000

    /// Whether the watch is over. Held while the footprint is read and the child stopped, so that after ``end()`` nothing is
    /// read or stopped.
    private let ended = Mutex(false)

    /// Watches `memory` from a thread of its own until ``end()``. Past `limit` bytes, `exceeded` is called and then the child
    /// stopped, once: who is told the child is gone already knows why.
    init(_ memory: CodemodeChild.Memory, limit: Int, exceeded: @escaping @Sendable () -> Void) {
        // The thread holds the watch until it is ended, which its keeper does whatever ends the script.
        DetachedThread.start(stackBytes: 64 << 10) { [self] in
            while true {
                let over = ended.withLock { ended in
                    guard !ended else { return true }
                    guard memory.footprint() > limit else { return false }
                    ended = true
                    exceeded()
                    memory.stop()
                    return true
                }
                if over { return }
                usleep(Self.interval)
            }
        }
    }

    /// Ends the watch: once this returns, the child is neither read nor stopped by it.
    func end() { ended.withLock { $0 = true } }
}
