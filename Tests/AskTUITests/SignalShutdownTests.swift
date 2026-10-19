internal import Foundation
internal import Synchronization
internal import TerminalKitCore
internal import TerminalKitIO
internal import TerminalKitInput
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
    private static let ladder = ContiguousArray(TerminalResetLadder.escapeBytes(upTo: .selectiveCleanup))

    /// A session already running full-screen on `connection`, as the screen leaves it when a signal lands.
    private static func entered(_ connection: any TerminalConnection) -> TerminalSession {
        let session = TerminalSession(connection: connection, modes: .fullScreen, keyboardProtocol: .probe)
        try? session.enter()
        return session
    }

    @Test func `the ladder is written before the process is asked to die`() {
        let connection = MockTerminalConnection()
        let exits = ExitRecorder()
        let shutdown = SignalShutdown(session: Self.entered(connection), onExit: exits.record)

        shutdown.handle(SIGTERM)

        #expect(Self.endsWith(connection.writtenOutput, Self.ladder))
        #expect(exits.codes == [128 + SIGTERM])
    }

    @Test func `termios is restored before the process is asked to die`() {
        let connection = MockTerminalConnection()
        let shutdown = SignalShutdown(session: Self.entered(connection), onExit: ExitRecorder().record)

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
        let exits = ExitRecorder()
        let shutdown = SignalShutdown(session: Self.entered(MockTerminalConnection()), onExit: exits.record)

        shutdown.handle(signal)

        #expect(exits.codes == [128 + signal], "\(name) should exit \(128 + signal)")
    }

    @Test func `a shutdown signal leaves the alternate screen`() {
        // Without the ladder the user is left in the alternate screen with the cursor hidden, which
        // is the exact failure this path exists to prevent.
        let connection = MockTerminalConnection()
        let session = Self.entered(connection)
        connection.clearOutput()

        SignalShutdown(session: session, onExit: ExitRecorder().record).handle(SIGTERM)

        #expect(Self.contains(connection.writtenOutput, ContiguousArray("\u{1B}[?1049l".utf8)))
    }

    @Test func `the signal path and the normal path restore the terminal once`() {
        let connection = MockTerminalConnection()
        let session = Self.entered(connection)

        SignalShutdown(session: session, onExit: ExitRecorder().record).handle(SIGTERM)
        session.leave()  // the screen's own exit path, still unwinding

        #expect(connection.restoreModeCallCount == 1)
    }

    @Test func `the terminal is restored even when the write fails`() {
        // A dead or detached terminal must not leave `termios` raw. The write is best-effort; the
        // restore is not.
        final class DetachingConnection: TerminalConnection {
            private let state = Mutex((writes: 0, restores: 0))

            var restoreCount: Int { state.withLock { $0.restores } }

            init() {}

            func read(into buffer: UnsafeMutableRawBufferPointer) throws(TerminalError) -> Int { 0 }
            func write(_ bytes: [UInt8]) throws(TerminalError) { try writeContiguous(ContiguousArray(bytes)) }
            func writeContiguous(_ bytes: ContiguousArray<UInt8>) throws(TerminalError) {
                // The entry write succeeds; the terminal is gone by the time the signal lands.
                let detached = state.withLock { state in
                    state.writes += 1
                    return state.writes > 1
                }
                if detached { throw .writeFailed(5) }
            }
            func enterRawMode() throws(TerminalError) {}
            func restoreMode() throws(TerminalError) { state.withLock { $0.restores += 1 } }
            func getSize() throws(TerminalError) -> TerminalSize { TerminalSize(columns: 80, rows: 24) }
        }

        let connection = DetachingConnection()
        let shutdown = SignalShutdown(session: Self.entered(connection), onExit: ExitRecorder().record)

        shutdown.handle(SIGTERM)

        #expect(connection.restoreCount == 1)
    }

    // MARK: - Helpers

    private static func endsWith(_ haystack: [UInt8], _ needle: ContiguousArray<UInt8>) -> Bool {
        haystack.count >= needle.count && Array(haystack.suffix(needle.count)) == Array(needle)
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

    private final class ExitRecorder: Sendable {
        private let recorded = Mutex<[Int32]>([])

        var codes: [Int32] { recorded.withLock { $0 } }

        func record(_ code: Int32) { recorded.withLock { $0.append(code) } }
    }
}
