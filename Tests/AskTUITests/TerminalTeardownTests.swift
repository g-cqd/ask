internal import Foundation
internal import Synchronization
internal import TerminalKitCore
internal import TerminalKitIO
internal import Testing

@testable import AskTUI

/// Every exit path has to leave the terminal usable, because the failure a user notices is not the
/// crash — it is the shell they are left staring at afterwards, in the alternate screen, with the
/// cursor hidden and echo off.
///
/// Raw mode clears `ISIG` (TerminalKit's `enterRawMode`), so Ctrl-C arrives as byte `0x03` rather than
/// as `SIGINT`, and the `return` in the loop is the normal quit path. The signals that *can* still
/// arrive are `SIGTERM` and `SIGHUP` — a `kill`, or the window closing — and those bypass every `defer`
/// in the loop. That is what this suite covers.
@Suite("Every exit path restores the terminal")
struct TerminalTeardownTests {
    /// The bytes that must reach the terminal on the way out: the frame closed, then the cheapest
    /// tier of the ladder.
    ///
    /// Tier 1 is the one that clears the private modes, because neither reset tier does — TerminalKit
    /// ADR-0002 measured that against four emulators.
    private static var expectedSuffix: ContiguousArray<UInt8> {
        var expected = ContiguousArray<UInt8>()
        expected.append(contentsOf: StartupSequence.end)
        expected.append(contentsOf: TerminalResetLadder.escapeBytes(upTo: .selectiveCleanup))
        return expected
    }

    private static func endsWith(_ haystack: [UInt8], _ needle: ContiguousArray<UInt8>) -> Bool {
        guard haystack.count >= needle.count else { return false }
        return Array(haystack.suffix(needle.count)) == Array(needle)
    }

    private static func run(_ connection: MockTerminalConnection, conversation: any Conversation = IdleConversation())
        async throws
    {
        let (resizes, done) = AsyncStream<Void>.makeStream()
        done.finish()
        try await runInteractiveScreen(on: connection, conversation: conversation, label: "m", resizes: resizes)
    }

    @Test func `quitting on Ctrl-D leaves the alternate screen and restores the cursor`() async throws {
        let connection = MockTerminalConnection()
        connection.feedInput([0x04])
        try await Self.run(connection)
        #expect(Self.endsWith(connection.writtenOutput, Self.expectedSuffix))
    }

    @Test func `quitting on Ctrl-C leaves the alternate screen and restores the cursor`() async throws {
        let connection = MockTerminalConnection()
        connection.feedInput([0x03])
        try await Self.run(connection)
        #expect(Self.endsWith(connection.writtenOutput, Self.expectedSuffix))
    }

    @Test func `a failed read ends the screen and still restores the terminal`() async throws {
        // The input source ends its stream on a read error, and the screen treats that as quitting. If the
        // ladder were written inline on one path it would be skipped on another.
        let connection = MockTerminalConnection()
        connection.enqueueReadError(.readFailed(5))
        try await Self.run(connection)
        #expect(Self.endsWith(connection.writtenOutput, Self.expectedSuffix))
    }

    @Test func `termios is restored on the normal quit path`() async throws {
        let connection = MockTerminalConnection()
        connection.feedInput([0x04])
        try await Self.run(connection)
        #expect(connection.isRawMode == false)
        #expect(connection.restoreModeCallCount == 1)
    }

    @Test func `a submitted prompt reaches the conversation and the screen`() async throws {
        let connection = MockTerminalConnection()
        connection.feedInput(Array("hi\r".utf8))
        let conversation = RecordingConversation()
        try await Self.run(connection, conversation: conversation)
        #expect(conversation.prompts == ["hi"])
        #expect(String(decoding: connection.writtenOutput, as: UTF8.self).contains("› hi"))
    }

    @Test func `Ctrl-C mid-turn cancels the run, and the screen waits for it to stop`() async throws {
        let connection = MockTerminalConnection()
        connection.feedInput(Array("go\r".utf8) + [0x03])
        let conversation = RecordingConversation(waitsForCancellation: true)
        try await Self.run(connection, conversation: conversation)
        #expect(conversation.cancelled)
        #expect(Self.endsWith(connection.writtenOutput, Self.expectedSuffix))
    }
}

/// Starts nothing.
private struct IdleConversation: Conversation {
    func start(_ prompt: String, update: @escaping @Sendable (ConversationUpdate) -> Void) -> Task<Void, Never> {
        Task { update(.runEnded) }
    }
}

/// Records prompts; optionally runs until cancelled, as a long tool call would.
private final class RecordingConversation: Conversation {
    private let state = Mutex<(prompts: [String], cancelled: Bool)>(([], false))
    private let waitsForCancellation: Bool

    init(waitsForCancellation: Bool = false) { self.waitsForCancellation = waitsForCancellation }

    var prompts: [String] { state.withLock { $0.prompts } }
    var cancelled: Bool { state.withLock { $0.cancelled } }

    private func markCancelled() { state.withLock { $0.cancelled = true } }

    func start(_ prompt: String, update: @escaping @Sendable (ConversationUpdate) -> Void) -> Task<Void, Never> {
        state.withLock { $0.prompts.append(prompt) }
        let waits = waitsForCancellation
        return Task {
            if waits {
                let stream = AsyncStream<Never> { _ in }
                for await _ in stream {}  // ends only when this task is cancelled
                self.markCancelled()
            }
            update(.runEnded)
        }
    }
}
