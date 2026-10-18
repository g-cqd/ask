internal import TerminalKitCore
internal import TerminalKitIO

/// Restores the terminal when a shutdown signal arrives, then asks the process to die.
///
/// Raw mode clears `ISIG`, so `Ctrl-C` arrives as byte `0x03` and never becomes `SIGINT`. The signals
/// that can still reach a running `ask` are `SIGTERM` (a `kill`), `SIGHUP` (the window closing) and
/// `SIGQUIT` — and all three bypass every `defer` in the read loop, which is how a terminal ends up
/// in the alternate screen with the cursor hidden and echo off.
///
/// **Restoring is not enough on its own.** A handler that swallowed the signal would leave a process
/// that ignores `kill`, which is worse to hand a user than a scrambled terminal. So the exit is a
/// separate, injected step, and this type is what runs before it.
///
/// The exit code follows the shell convention `128 + signo` so a supervising shell reports the exit
/// as signalled rather than as a plain failure.
struct SignalShutdown: Sendable {
    private let connection: any TerminalConnection
    private let onExit: @Sendable (Int32) -> Void

    /// - Parameters:
    ///   - connection: the terminal to restore.
    ///   - onExit: asked to end the process with the given code, after the terminal is restored.
    ///     Injected so the sequence can be tested; production passes `exit`.
    init(connection: any TerminalConnection, onExit: @escaping @Sendable (Int32) -> Void) {
        self.connection = connection
        self.onExit = onExit
    }

    /// Restores the terminal, then requests the exit.
    ///
    /// Restore first, always: a terminal that cannot be written to must still have its `termios`
    /// put back, and ``TerminalTeardown/run(on:)`` ignores a write failure for exactly that reason.
    ///
    /// - Parameter signal: the signal number that arrived.
    /// - Complexity: O(1) — a fixed byte sequence, not a function of screen size.
    func handle(_ signal: Int32) {
        TerminalTeardown.run(on: connection)
        onExit(128 + signal)
    }
}
