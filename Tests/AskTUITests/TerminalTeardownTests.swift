internal import Foundation
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

    @Test func `quitting on Ctrl-D leaves the alternate screen and restores the cursor`() throws {
        let connection = MockTerminalConnection()
        connection.feedInput([0x04])

        try runAskTUI(on: connection)

        #expect(Self.endsWith(connection.writtenOutput, Self.expectedSuffix))
    }

    @Test func `quitting on Ctrl-C leaves the alternate screen and restores the cursor`() throws {
        let connection = MockTerminalConnection()
        connection.feedInput([0x03])

        try runAskTUI(on: connection)

        #expect(Self.endsWith(connection.writtenOutput, Self.expectedSuffix))
    }

    @Test func `a failed read still restores the terminal`() throws {
        // The read loop is the only place `runAskTUI` can throw. If the ladder were written inline on
        // the normal return it would be skipped here, and a user who hits an I/O error gets a broken
        // shell.
        let connection = MockTerminalConnection()
        connection.enqueueReadError(.readFailed(5))

        #expect(throws: (any Error).self) {
            try runAskTUI(on: connection)
        }

        #expect(Self.endsWith(connection.writtenOutput, Self.expectedSuffix))
    }

    @Test func `termios is restored on the normal quit path`() {
        let connection = MockTerminalConnection()
        connection.feedInput([0x04])

        #expect(throws: Never.self) { try runAskTUI(on: connection) }

        #expect(connection.isRawMode == false)
        #expect(connection.restoreModeCallCount == 1)
    }
}
