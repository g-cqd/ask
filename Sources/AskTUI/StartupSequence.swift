/// The terminal's entry and exit sequences for `ask`'s interactive screen (see `InteractiveScreen`).
///
/// Nothing here is instrumented into the hot path. Timings are taken externally, from a PTY, because
/// a program that reports its own latency reports the flattering number.

internal import Foundation
internal import TerminalKitCodecs
internal import TerminalKitCore
internal import TerminalKitIO
internal import TerminalKitInput

/// Everything written before the first frame: alternate screen, cursor hidden, screen cleared, and
/// the frame bracketed by synchronised-output markers so it cannot tear.
enum StartupSequence {
    static var begin: [UInt8] {
        EscapeSequences.enterAlternateScreen
            + EscapeSequences.hideCursor
            + EscapeSequences.clearScreen
            + EscapeSequences.beginSyncUpdate
    }

    static var end: [UInt8] { EscapeSequences.endSyncUpdate + EscapeSequences.showCursor }
}
