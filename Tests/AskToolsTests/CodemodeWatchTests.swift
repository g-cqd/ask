import AskCodemode
import Synchronization
import Testing

@testable import AskTools

/// A keeper's watch over the memory of a script's process, from outside it (ADR-0156). The memory here is a made-up one, read
/// as the test says: nothing waits on how fast a real process grows.
@Suite("A script's memory is watched from outside its process", .timeLimit(.minutes(1)))
struct CodemodeWatchTests {
    /// A child's memory that reads as `readings` say, the last of them from then on, and records what is done to it.
    private final class Fake: Sendable {
        let events = Mutex<[String]>([])
        let stopped = AsyncStream<Void>.makeStream()
        private let readings: Mutex<[Int]>

        init(_ readings: [Int]) { self.readings = Mutex(readings) }

        var memory: CodemodeChild.Memory {
            CodemodeChild.Memory(
                footprint: { [self] in
                    events.withLock { $0.append("read") }
                    return readings.withLock { $0.count > 1 ? $0.removeFirst() : $0[0] }
                },
                stop: { [self] in
                    events.withLock { $0.append("stopped") }
                    stopped.continuation.yield()
                }
            )
        }
    }

    @Test func `a child is left alone at its limit, and stopped past it, after its keeper is told why`() async {
        let fake = Fake([0, 100, 101])
        let watch = CodemodeWatch(fake.memory, limit: 100) { fake.events.withLock { $0.append("exceeded") } }
        for await _ in fake.stopped.stream { break }
        watch.end()
        #expect(fake.events.withLock { $0 } == ["read", "read", "read", "exceeded", "stopped"])
    }

    /// What it said crosses before its call does, and its memory reads as too much only once that call has arrived.
    @Test func `a script whose process passes its memory is stopped by its keeper, and keeps what it had said`() async {
        let said = [CodemodeItem(text: "before")]
        let taken = Mutex(0)
        let never = AsyncStream<Void>.makeStream()
        let result = await CodemodeKeeper(
            start: CodemodeChildren.saying(said) { taken.withLock { $0 } },
            scripts: CodemodeLimiter(1)
        )
        .run("x", tools: [], limits: CodemodeLimits(deadline: .seconds(300), memoryMiB: 64)) { _, _ in
            taken.withLock { $0 = (64 << 20) + 1 }
            // Answered only by the script's end: the wait is over when the call is cancelled.
            for await _ in never.stream {}
            return .success("")
        }
        let expected = CodemodeResult(
            items: said,
            failure: "The script took more than 64 MiB of memory and was stopped."
        )
        #expect(result == expected)
    }

    @Test func `a child that watches itself is not watched`() async {
        let child = await CodemodeChildren.inProcess(64)
        #expect(child?.memory == nil)
        _ = await child?.close()
    }
}
