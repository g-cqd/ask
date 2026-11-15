import Synchronization
import Testing

@testable import AskTools

@Suite("No more than its limit hold a place at once, and a cancelled wait takes none", .timeLimit(.minutes(1)))
struct CodemodeLimiterTests {
    @Test func `places are taken up to the limit, and the next waits for a release`() async {
        let limiter = CodemodeLimiter(2)
        #expect(await limiter.acquire())
        #expect(limiter.free == 1)
        #expect(await limiter.acquire())
        #expect(limiter.free == 0)
        let third = Task { await limiter.acquire() }
        await limiter.waiting(1)
        limiter.release()
        #expect(await third.value)
        #expect(limiter.free == 0, "the place went to the one that waited")
    }

    @Test func `never more than the limit run at once, whatever asks`() async {
        let limiter = CodemodeLimiter(3)
        // Held by the test: whoever has a place waits here, so the places stay taken until the test has looked.
        let gate = CodemodeLimiter(1)
        #expect(await gate.acquire())
        let running = Mutex((now: 0, most: 0))
        await withTaskGroup(of: Void.self) { group in
            for _ in 0 ..< 40 {
                group.addTask {
                    guard await limiter.acquire() else { return }
                    running.withLock { state in
                        state.now += 1
                        state.most = max(state.most, state.now)
                    }
                    if await gate.acquire() { gate.release() }
                    running.withLock { $0.now -= 1 }
                    limiter.release()
                }
            }
            // Thirty-seven wait for a place: the other three have one, all at once.
            await limiter.waiting(37)
            #expect(running.withLock { $0.now } == 3)
            gate.release()
        }
        #expect(running.withLock { $0.most } == 3)
        #expect(limiter.free == 3)
    }

    @Test func `a wait that is cancelled takes no place, and the place is still there for the next`() async {
        let limiter = CodemodeLimiter(1)
        #expect(await limiter.acquire())
        let waiting = Task { await limiter.acquire() }
        await limiter.waiting(1)
        waiting.cancel()
        #expect(await waiting.value == false)
        limiter.release()
        #expect(limiter.free == 1)
        #expect(limiter.free == 1)
    }
}
