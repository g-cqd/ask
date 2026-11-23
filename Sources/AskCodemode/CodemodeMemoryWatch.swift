internal import Dispatch
internal import Foundation
internal import Synchronization

/// A watch over the host's memory that looks only while a script runs (energy audit 2026-11-22, ENG-03): the host stays between
/// scripts, and a watch that looked every 2 ms then woke it 500 times a second for nothing. While a script runs it looks every
/// `interval`, as a script can take 10 MB a millisecond; between scripts its thread sleeps until the next one begins.
package final class CodemodeMemoryWatch: Sendable {
    /// How many scripts are running, and how many times the memory was read, for tests.
    private let running = Mutex(0)
    private let readings = Atomic<Int>(0)
    private let wake = DispatchSemaphore(value: 0)

    /// How many times the memory has been read.
    package var reads: Int { readings.load(ordering: .relaxed) }

    /// Starts the watch's thread. Past `limit` bytes while a script runs, `exceeded` is called, once.
    package init(
        limit: Int,
        interval: UInt32 = 2000,
        footprint: @escaping @Sendable () -> Int = CodemodeMemory.footprint,
        exceeded: @escaping @Sendable () -> Void
    ) {
        Thread.detachNewThread { [self] in
            while true {
                guard running.withLock({ $0 }) > 0 else {
                    wake.wait()
                    continue
                }
                readings.add(1, ordering: .relaxed)
                if footprint() > limit {
                    exceeded()
                    return
                }
                usleep(interval)
            }
        }
    }

    /// A script begins: the watch looks until every script that began has ended.
    package func began() {
        let first = running.withLock { count in
            count += 1
            return count == 1
        }
        if first { wake.signal() }
    }

    /// A script has ended.
    package func ended() { running.withLock { $0 = max(0, $0 - 1) } }
}
