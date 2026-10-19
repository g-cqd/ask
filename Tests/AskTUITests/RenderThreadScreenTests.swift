internal import Dispatch
internal import Foundation
internal import Synchronization
internal import TerminalKitIO
internal import Testing

@testable import AskTUI

/// The screen is drawn on TerminalKit's render thread (its ADR-0026): a key is handled while a frame is still being
/// written, and the last frame is out before the terminal is restored.
@Suite("The screen handles keys while a frame is being written")
struct RenderThreadScreenTests {
    /// A terminal whose second write, the first frame, blocks until released.
    private final class StallingFirstFrame: TerminalConnection {
        private let inner = MockTerminalConnection()
        private let writes = Atomic<Int>(0)
        let stalled = DispatchSemaphore(value: 0)
        private let release = DispatchSemaphore(value: 0)

        var output: [UInt8] { inner.writtenOutput }
        func feedInput(_ bytes: [UInt8]) { inner.feedInput(bytes) }
        func waitUntilStalled() { stalled.wait() }
        func releaseFrame() { release.signal() }

        func read(into buffer: UnsafeMutableRawBufferPointer) throws(TerminalError) -> Int {
            try inner.read(into: buffer)
        }
        func write(_ bytes: [UInt8]) throws(TerminalError) { try writeContiguous(ContiguousArray(bytes)) }
        func writeContiguous(_ bytes: ContiguousArray<UInt8>) throws(TerminalError) {
            if writes.add(1, ordering: .acquiringAndReleasing).newValue == 2 {
                stalled.signal()
                release.wait()
            }
            try inner.writeContiguous(bytes)
        }
        func enterRawMode() throws(TerminalError) { try inner.enterRawMode() }
        func restoreMode() throws(TerminalError) { try inner.restoreMode() }
        func getSize() throws(TerminalError) -> TerminalSize { try inner.getSize() }
    }

    /// Reports each prompt it is given.
    private struct Prompts: Conversation {
        let sink: AsyncStream<String>.Continuation

        func start(_ prompt: String, update: @escaping @Sendable (ConversationUpdate) -> Void) -> Task<Void, Never> {
            sink.yield(prompt)
            return Task { update(.runEnded) }
        }
    }

    @Test func `a submitted prompt reaches the conversation while the first frame is stuck in a write`() async throws {
        let connection = StallingFirstFrame()
        connection.feedInput(Array("go\r".utf8))
        let (prompts, sink) = AsyncStream<String>.makeStream()
        let (resizes, done) = AsyncStream<Void>.makeStream()
        done.finish()
        let screen = Task {
            try await runInteractiveScreen(
                on: connection, conversation: Prompts(sink: sink), label: "m", resizes: resizes)
        }

        connection.waitUntilStalled()  // the first frame is in a write that will not return
        var received = prompts.makeAsyncIterator()
        let prompt = await received.next()  // handled all the same
        connection.releaseFrame()
        _ = try await screen.value

        #expect(prompt == "go")
    }

    @Test func `the last frame is written before the terminal is restored`() async throws {
        let connection = MockTerminalConnection()
        connection.feedInput(Array("typed".utf8) + [0x15, 0x04])  // typed, cleared with Ctrl-U, then Ctrl-D quits
        let (resizes, done) = AsyncStream<Void>.makeStream()
        done.finish()

        try await runInteractiveScreen(
            on: connection, conversation: StubConversation(), label: "m", notices: ["the notice"], resizes: resizes)

        let output = String(decoding: connection.writtenOutput, as: UTF8.self)
        let noticeAt = try #require(output.range(of: "the notice"))
        let restoredAt = try #require(output.range(of: "\u{1B}[?1049l"))
        #expect(noticeAt.lowerBound < restoredAt.lowerBound)
        #expect(connection.restoreModeCallCount == 1)
    }

    private struct StubConversation: Conversation {
        func start(_ prompt: String, update: @escaping @Sendable (ConversationUpdate) -> Void) -> Task<Void, Never> {
            Task { update(.runEnded) }
        }
    }
}
