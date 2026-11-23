import Foundation
import Synchronization
import Testing

@testable import AskCodemode

/// The host's memory watch looks only while a script runs (energy audit 2026-11-22, ENG-03): between scripts it reads nothing, so an
/// idle host is not woken 500 times a second; while one runs it reads every interval, and past the limit it calls once.
@Suite("The memory watch looks only while a script runs")
struct CodemodeMemoryWatchTests {
    @Test func `idle it reads nothing; running it reads; ended it stops`() {
        let watch = CodemodeMemoryWatch(
            limit: .max,
            interval: 1000,
            footprint: { 0 },
            exceeded: { Issue.record("never over") }
        )
        usleep(100_000)
        #expect(watch.reads == 0, "idle: \(watch.reads) readings")
        watch.began()
        usleep(100_000)
        let running = watch.reads
        #expect(running > 20, "running: \(running) readings in 100 ms")
        watch.ended()
        usleep(20_000)
        let after = watch.reads
        usleep(100_000)
        #expect(watch.reads == after, "ended: \(watch.reads - after) more readings")
        watch.began()
        watch.began()
        watch.ended()
        usleep(50_000)
        #expect(watch.reads > after, "one of two scripts still runs")
        watch.ended()
    }

    @Test func `past the limit while a script runs, it calls once`() {
        let calls = Atomic<Int>(0)
        let size = Atomic<Int>(0)
        let watch = CodemodeMemoryWatch(
            limit: 100,
            interval: 500,
            footprint: { size.load(ordering: .relaxed) },
            exceeded: { calls.add(1, ordering: .relaxed) }
        )
        size.store(500, ordering: .relaxed)
        usleep(30_000)
        #expect(calls.load(ordering: .relaxed) == 0, "idle: not looked at")
        watch.began()
        usleep(50_000)
        #expect(calls.load(ordering: .relaxed) == 1)
    }
}
