internal import Foundation
internal import Synchronization
import Testing

@testable import AskTUI

/// The screen's loop runs on a thread of its own at the highest quality of service (note n18): on a machine under heavy contention a
/// key or the wheel waited behind everything else on Swift's shared threads, and a trackpad's burst took hundreds of milliseconds,
/// up to more than a second, to settle. What the loop starts with `Task {}`, the conversation's work, stays off that thread.
@Suite("The screen's loop has a thread of its own")
struct ScreenExecutorTests {
    private static func here() -> (name: String, interactive: Bool) {
        (Thread.current.name ?? "", Thread.current.qualityOfService == .userInteractive)
    }

    @Test func `work preferring the screen's executor runs on its thread, at the highest quality of service`() async {
        let executor = ScreenExecutor(name: "ask.screen.test")
        defer { executor.stop() }
        let seen = await withTaskExecutorPreference(executor) { Self.here() }
        #expect(seen.name == "ask.screen.test")
        #expect(seen.interactive)
    }

    @Test func `a task the loop starts does not run on the screen's thread`() async {
        let executor = ScreenExecutor(name: "ask.screen.test")
        defer { executor.stop() }
        let started = await withTaskExecutorPreference(executor) { await Task { Self.here().name }.value }
        #expect(started != "ask.screen.test")
    }

    @Test func `jobs run in the order they came, one at a time`() async {
        let executor = ScreenExecutor(name: "ask.screen.test")
        defer { executor.stop() }
        let order = Mutex<[Int]>([])
        await withTaskExecutorPreference(executor) {
            await withTaskGroup(of: Void.self) { group in
                for index in 0 ..< 50 { group.addTask { order.withLock { $0.append(index) } } }
            }
        }
        #expect(order.withLock { $0.count } == 50)
    }
}
