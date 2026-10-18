/// The terminal loop of `ask`.
///
/// This is the smallest program that exercises the whole path a real agent needs: raw mode, the
/// alternate screen, synchronised output, input decoding, a redraw, and an ordered teardown. It
/// exists so the performance budgets can be **measured** against a real binary rather than argued
/// about — every number this project will later quote starts here.
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

/// `ESC [ K` — erase from the cursor to the end of the line. One byte sequence, no repaint of the
/// rest of the line, which is what keeps a keystroke's cost proportional to the line rather than the
/// screen.
private let eraseToEndOfLine: [UInt8] = [0x1B, 0x5B, 0x4B]

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

/// Runs the terminal loop until the user quits, then restores the terminal.
public func runAskTUI() throws {
    let connection = POSIXTerminalConnection()

    // Raw mode clears `ISIG`, so Ctrl-C arrives as byte `0x03` rather than SIGINT. The signals that
    // can still reach us are SIGINT and SIGTERM, and both bypass every `defer` in the read loop —
    // which is how a terminal ends up in the alternate screen with the cursor hidden and echo off.
    //
    // TerminalKit delivers these off the main thread (TerminalKit ADR-0013), so a blocked read cannot
    // starve delivery, and it reports which signal fired — which is what `128 + signo` needs.
    let shutdown = SignalShutdown(connection: connection) { code in exit(code) }
    try SignalHandler(onResize: {}, onShutdown: { shutdown.handle($0) }).start()

    try runAskTUI(on: connection)
}

/// The loop, over an injected connection.
///
/// The connection is a parameter so that every exit path is drivable from a test — see
/// ``TerminalTeardownTests``. The production entry point above is the one that binds a real terminal.
internal func runAskTUI(on connection: any TerminalConnection) throws {
    try connection.enterRawMode()
    defer { TerminalTeardown.run(on: connection) }

    _ = try connection.getSize()
    var output = ContiguousArray<UInt8>()
    output.append(contentsOf: StartupSequence.begin)
    output.append(contentsOf: promptBytes(line: ""))
    try connection.writeContiguous(output)

    let buffer = UnsafeMutableRawBufferPointer.allocate(byteCount: 4096, alignment: 8)
    defer { buffer.deallocate() }

    var line = ""
    while true {
        let count = try connection.read(into: buffer)
        guard count > 0 else { continue }

        var redraw = ContiguousArray<UInt8>()
        redraw.append(contentsOf: EscapeSequences.beginSyncUpdate)
        var submitted = false

        for index in 0 ..< count {
            let byte = buffer[index]
            switch byte {
                case 0x03, 0x04:
                    return  // Ctrl-C, Ctrl-D
                case 0x1B:
                    // An escape sequence. Discard the rest of it rather than render half of it.
                    return
                case 0x0D, 0x0A:
                    submitted = true
                    redraw.append(contentsOf: "\r\n".utf8)
                case 0x7F, 0x08:
                    if !line.isEmpty { line.removeLast() }
                    redraw.append(contentsOf: promptBytes(line: line))
                    redraw.append(contentsOf: eraseToEndOfLine)
                case 0x20 ... 0x7E:
                    line.append(Character(UnicodeScalar(byte)))
                    redraw.append(contentsOf: promptBytes(line: line))
                default:
                    break
            }
        }

        if submitted {
            redraw.append(contentsOf: promptBytes(line: ""))
            line = ""
        }
        redraw.append(contentsOf: EscapeSequences.endSyncUpdate)
        try connection.writeContiguous(redraw)

        if submitted, line.isEmpty, redraw.count > 8 {
            // A bare Enter re-prompts; nothing else to do.
            continue
        }
    }
}

/// The prompt plus the current line.
private func promptBytes(line: String) -> ContiguousArray<UInt8> {
    var bytes = ContiguousArray<UInt8>()
    bytes.append(contentsOf: "\r".utf8)
    bytes.append(contentsOf: "ask> ".utf8)
    bytes.append(contentsOf: line.utf8)
    return bytes
}
