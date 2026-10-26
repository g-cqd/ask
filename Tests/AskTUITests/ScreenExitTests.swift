internal import Foundation
internal import Synchronization
internal import TerminalKitCore
internal import TerminalKitIO
internal import Testing

@testable import AskTUI

/// How the screen closes: a command can ask for a reason to be returned, and whatever watches in the background
/// lives and dies with the screen. (The close itself, after the command's run, is exercised on a real terminal
/// in `Scripts/probe-interactive.py`: a mock's input ends the instant its buffer is empty, which races the run.)
@Suite("A command can ask for the screen to close with a reason, and background watchers follow the screen")
struct ScreenExitTests {
    private func run(_ connection: MockTerminalConnection, _ conversation: any Conversation) async throws -> ScreenExit
    {
        let (resizes, done) = AsyncStream<Void>.makeStream()
        done.finish()
        return try await runInteractiveScreen(
            on: connection, conversation: conversation, label: "m", resizes: resizes)
    }

    @Test func `a request to exit is remembered by the controller, and nothing closes before it is made`() {
        var controller = ScreenController(label: "m", options: .legacy)
        #expect(controller.state.exitRequest == nil)
        controller.handle(.requestExit(.reload))
        #expect(controller.state.exitRequest == .reload)
    }

    @Test func `quitting is a quit`() async throws {
        let connection = MockTerminalConnection()
        connection.feedInput([0x04])
        #expect(try await run(connection, Watching()) == .quit)
    }

    @Test func `whatever watches in the background is started with the screen and stopped when it closes`() async throws
    {
        let connection = MockTerminalConnection()
        connection.feedInput([0x04])
        let conversation = Watching()
        _ = try await run(connection, conversation)
        #expect(conversation.watchStarted)
        // The watching task ends only when cancelled: this returns once the screen cancelled it.
        await conversation.watching?.value
    }

    @Test func `what the background reports reaches the transcript`() async throws {
        let connection = MockTerminalConnection()
        connection.feedInput([0x04])
        _ = try await run(connection, Watching(announces: "A new ask appeared."))
        #expect(String(decoding: connection.writtenOutput, as: UTF8.self).contains("A new ask appeared."))
    }

    /// Watches in the background, until cancelled; announces something at once if told to.
    private final class Watching: Conversation {
        private let state = Mutex<(watchStarted: Bool, watching: Task<Void, Never>?)>((false, nil))
        private let announces: String?

        init(announces: String? = nil) { self.announces = announces }

        var watchStarted: Bool { state.withLock { $0.watchStarted } }
        var watching: Task<Void, Never>? { state.withLock { $0.watching } }

        func start(_ prompt: String, update: @escaping @Sendable (ConversationUpdate) -> Void) -> Task<Void, Never> {
            Task { update(.runEnded) }
        }

        func background(update: @escaping @Sendable (ConversationUpdate) -> Void) -> Task<Void, Never>? {
            // Announced before the screen reads any input, so it cannot lose a race with the input ending.
            if let announces { update(.notice(announces, isError: false)) }
            let (stream, _) = AsyncStream<Never>.makeStream()
            let task = Task { for await _ in stream {} }
            state.withLock {
                $0.watchStarted = true
                $0.watching = task
            }
            return task
        }
    }
}
