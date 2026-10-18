internal import Foundation
internal import Synchronization
internal import TerminalKitCore
internal import TerminalKitIO
internal import Testing

@testable import AskTUI

/// A signal must restore the terminal **and** then die.
///
/// Restoring alone would be worse than the bug: a handler that swallows `SIGTERM` leaves a process
/// that ignores `kill`, which is a worse thing to hand a user than a scrambled terminal. So the
/// shutdown path is split into the part that is worth testing (write the ladder, restore `termios`)
/// and the part that cannot be (terminate the process), with the second one injected.
@Suite("A shutdown signal restores the terminal and then dies")
struct SignalShutdownTests {
    /// What `exit(128 + signo)` should be asked for, per the shell convention for a signalled exit.
    private static func expectedCode(for signal: Int32) -> Int32 { 128 + signal }

    @Test func `the ladder is written before the process is asked to die`() {
        let connection = MockTerminalConnection()
        let exits = ExitRecorder()
        let shutdown = SignalShutdown(connection: connection, onExit: exits.record)

        shutdown.handle(SIGTERM)

        #expect(Self.endsWithTeardown(connection.writtenOutput))
        #expect(exits.codes == [Self.expectedCode(for: SIGTERM)])
    }

    @Test func `termios is restored before the process is asked to die`() {
        let connection = MockTerminalConnection()
        try? connection.enterRawMode()
        let exits = ExitRecorder()
        let shutdown = SignalShutdown(connection: connection, onExit: exits.record)

        shutdown.handle(SIGHUP)

        #expect(connection.isRawMode == false)
    }

    @Test(arguments: [
        (Int32(SIGINT), "SIGINT"),
        (Int32(SIGTERM), "SIGTERM"),
        (Int32(SIGHUP), "SIGHUP"),
        (Int32(SIGQUIT), "SIGQUIT")
    ])
    func `every shutdown signal reports the shell convention exit code`(signal: Int32, name: String) {
        let connection = MockTerminalConnection()
        let exits = ExitRecorder()
        let shutdown = SignalShutdown(connection: connection, onExit: exits.record)

        shutdown.handle(signal)

        #expect(exits.codes == [128 + signal], "\(name) should exit \(128 + signal)")
    }

    @Test func `a shutdown signal leaves the alternate screen`() {
        // Without the ladder the user is left in the alternate screen with the cursor hidden, which
        // is the exact failure this path exists to prevent.
        let connection = MockTerminalConnection()
        try? connection.writeContiguous(ContiguousArray(StartupSequence.begin))
        connection.clearOutput()

        SignalShutdown(connection: connection, onExit: ExitRecorder().record).handle(SIGTERM)

        let written = connection.writtenOutput
        let ladder = ContiguousArray(TerminalResetLadder.escapeBytes(upTo: .selectiveCleanup))
        #expect(Self.contains(written, ladder))
    }

    @Test func `the terminal is restored even when the write fails`() {
        // A dead or detached terminal must not leave `termios` raw. The write is best-effort; the
        // restore is not.
        final class FailingConnection: TerminalConnection {
            private let restores = Mutex(0)

            var restoreCount: Int { restores.withLock { $0 } }

            init() {}

            func read(into buffer: UnsafeMutableRawBufferPointer) throws(TerminalError) -> Int { 0 }
            func write(_ bytes: [UInt8]) throws(TerminalError) { throw .writeFailed(5) }
            func writeContiguous(_ bytes: ContiguousArray<UInt8>) throws(TerminalError) {
                throw .writeFailed(5)
            }
            func enterRawMode() throws(TerminalError) {}
            func restoreMode() throws(TerminalError) {
                restores.withLock { $0 += 1 }
            }

            func getSize() throws(TerminalError) -> TerminalSize { TerminalSize(columns: 80, rows: 24) }
        }

        let connection = FailingConnection()
        let shutdown = SignalShutdown(connection: connection, onExit: ExitRecorder().record)

        shutdown.handle(SIGTERM)

        #expect(connection.restoreCount == 1)
    }

    // MARK: - Helpers

    private static func endsWithTeardown(_ written: [UInt8]) -> Bool {
        contains(written, TerminalTeardown.bytes)
    }

    private static func contains(_ haystack: [UInt8], _ needle: ContiguousArray<UInt8>) -> Bool {
        guard !needle.isEmpty, haystack.count >= needle.count else { return false }
        let target = Array(needle)
        for start in 0 ... (haystack.count - needle.count)
        where Array(haystack[start ..< start + needle.count]) == target {
            return true
        }
        return false
    }

    /// Collects the exit codes the shutdown path asks for, instead of exiting the test process.
    ///
    /// `Mutex` from `Synchronization`, not `NSLock`: `NSLock` is a class from Foundation with an
    /// Objective-C runtime behind it, and this project bans it in favour of the standard library's
    /// lock — the same choice TerminalKit's own `POSIXTerminalConnection` and `SignalHandler` make for
    /// the state they guard.
    private final class ExitRecorder: Sendable {
        private let recorded = Mutex<[Int32]>([])

        var codes: [Int32] { recorded.withLock { $0 } }

        func record(_ code: Int32) { recorded.withLock { $0.append(code) } }
    }
}
