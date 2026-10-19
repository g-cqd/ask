internal import Foundation
internal import TerminalKitCodecs
internal import TerminalKitCore
internal import TerminalKitIO
internal import TerminalKitInput

/// Everything written on the way out: the frame closed, then the cheapest tier of the reset ladder.
///
/// Tier 1 is the tier that clears the private modes, because neither reset tier does — TerminalKit
/// ADR-0002 measured that against four emulators, leaving `?1049`, the mouse modes and `?2004` set
/// across DECSTR. So the normal path writes this and nothing above it.
///
/// It exists as a named value rather than inline in a `defer` so that every exit path — normal quit,
/// thrown error, and the signal path — writes the same bytes, and so a test can assert them.
enum TerminalTeardown {
    /// The bytes that return the terminal to a usable state.
    static var bytes: ContiguousArray<UInt8> {
        var teardown = ContiguousArray<UInt8>()
        teardown.append(contentsOf: StartupSequence.end)
        teardown.append(contentsOf: TerminalResetLadder.escapeBytes(upTo: .selectiveCleanup))
        return teardown
    }

    /// Writes the teardown and restores termios, in that order, ignoring a write failure.
    ///
    /// The order matters: leaving the alternate screen while the cursor is still hidden would leave a
    /// visible cursor on the normal screen, and a terminal that cannot be written to is a terminal
    /// whose `termios` still needs restoring.
    ///
    /// - Complexity: O(1) — a fixed 60-odd byte sequence, not a function of screen size.
    static func run(on connection: any TerminalConnection) {
        try? connection.writeContiguous(bytes)
        try? connection.restoreMode()
    }
}
