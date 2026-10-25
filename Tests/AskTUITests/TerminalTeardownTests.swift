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
    /// TerminalKit's session ends every exit with tier 1 of the reset ladder (its ADR-0019).
    private static var expectedSuffix: ContiguousArray<UInt8> {
        ContiguousArray(TerminalResetLadder.escapeBytes(upTo: .selectiveCleanup))
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

    @Test func `quitting on a second Ctrl-C leaves the alternate screen and restores the cursor`() async throws {
        let connection = MockTerminalConnection()
        connection.feedInput([0x03, 0x03])
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

    @Test func `bracketed paste is on while the screen runs, so a pasted newline is not Enter`() async throws {
        let connection = MockTerminalConnection()
        connection.feedInput(Array("\u{1B}[200~one\ntwo\u{1B}[201~\r".utf8))
        let conversation = RecordingConversation()
        try await Self.run(connection, conversation: conversation)
        let output = connection.writtenOutput
        let enable = Array("\u{1B}[?2004h".utf8)
        let disable = Array("\u{1B}[?2004l".utf8)
        let enabledAt = try #require(Self.firstIndex(of: enable, in: output))
        let disabledAt = try #require(Self.firstIndex(of: disable, in: output, after: enabledAt))
        #expect(enabledAt < disabledAt)
        #expect(
            conversation.prompts == ["one\ntwo"], "the paste is one two-line prompt, submitted by the Enter after it")
    }

    private static func firstIndex(of needle: [UInt8], in haystack: [UInt8], after start: Int = 0) -> Int? {
        guard haystack.count >= needle.count, start <= haystack.count - needle.count else { return nil }
        return (start ... (haystack.count - needle.count))
            .first { Array(haystack[$0 ..< ($0 + needle.count)]) == needle }
    }

    @Test func `the screen asks the terminal about its keyboard without waiting for the answer`() async throws {
        // The mock never answers, and the screen still runs and quits.
        let connection = MockTerminalConnection()
        connection.feedInput([0x04])
        try await Self.run(connection)
        #expect(Self.firstIndex(of: Array("\u{1B}[?u\u{1B}[c".utf8), in: connection.writtenOutput) != nil)
    }

    @Test func `a kitty keyboard reply turns on disambiguated keys, and quitting turns them off`() async throws {
        let connection = MockTerminalConnection()
        connection.feedInput(Array("\u{1B}[?0u\u{1B}[?62;52c".utf8) + [0x04])
        try await Self.run(connection)
        let output = connection.writtenOutput
        let pushedAt = try #require(Self.firstIndex(of: Array("\u{1B}[>1u".utf8), in: output))
        #expect(Self.firstIndex(of: Array("\u{1B}[<u".utf8), in: output, after: pushedAt) != nil)
    }

    @Test func `the terminal's replies never reach the prompt`() async throws {
        let connection = MockTerminalConnection()
        connection.feedInput(Array("\u{1B}[?0u\u{1B}[?62;52chi\r".utf8))
        let conversation = RecordingConversation()
        try await Self.run(connection, conversation: conversation)
        #expect(conversation.prompts == ["hi"])
    }

    @Test func `the screen opens with the notices it was given`() async throws {
        let connection = MockTerminalConnection()
        connection.feedInput([0x04])
        let (resizes, done) = AsyncStream<Void>.makeStream()
        done.finish()
        try await runInteractiveScreen(
            on: connection, conversation: IdleConversation(), label: "m",
            notices: ["Instructions loaded from /p/AGENTS.md."], resizes: resizes)
        #expect(
            String(decoding: connection.writtenOutput, as: UTF8.self).contains("Instructions loaded from /p/AGENTS.md.")
        )
    }

    @Test func `a submitted prompt reaches the conversation and the screen`() async throws {
        let connection = MockTerminalConnection()
        let prompt = "transcript evidence 739"
        connection.feedInput(Array((prompt + "\r").utf8))
        let conversation = RecordingConversation()
        try await Self.run(connection, conversation: conversation)
        #expect(conversation.prompts == [prompt])
        #expect(String(decoding: connection.writtenOutput, as: UTF8.self).contains(prompt))
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
        // @al:accept -- a test double: the task ends only when the test cancels it, and the object lives for that test alone
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
