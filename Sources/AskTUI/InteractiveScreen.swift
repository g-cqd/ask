internal import Foundation
internal import TerminalKitIO
internal import TerminalKitInput
internal import TerminalKitRender

/// Runs the interactive screen on the terminal until the user quits, then restores the terminal.
///
/// SIGINT and SIGTERM still restore the terminal (raw mode clears `ISIG`, so Ctrl-C arrives as a key and
/// means "abort the turn" or "quit"). SIGWINCH redraws at the new size.
///
/// Nothing here runs on the main actor: input is read on its own thread, this loop only applies events to the
/// screen's state, and a render thread draws the newest state (TerminalKit ADR-0023, ADR-0026). A key is handled
/// whatever a frame costs.
/// - Parameters:
///   - conversation: runs each submitted prompt.
///   - label: shown at the left of the status line.
///   - history: a resumed session's conversation, shown before anything else.
///   - notices: shown after the history, such as a file that was ignored.
///   - details: shown after those only when details are on (`--verbose`, `/verbose`), and kept for `/verbose` otherwise.
///   - options: how the pointer behaves: whether it is reported, whether a selection is copied, how far the wheel scrolls.
///   - beforeSignalExit: runs when a shutdown signal is about to end the process, after the terminal is
///     restored: the last chance to stop child processes.
/// - Returns: why the screen closed.
/// - Throws: when the terminal cannot be set up.
@discardableResult
public func runInteractiveScreen(
    conversation: any Conversation, label: String, history: [ConversationUpdate] = [], notices: [String] = [],
    details: [String] = [], options: ScreenOptions = ScreenOptions(),
    beforeSignalExit: @escaping @Sendable () -> Void = {}
) async throws -> ScreenExit {
    // Frames and the session's own escape sequences share one terminal, so their writes take turns.
    let connection = SerializedConnection(POSIXTerminalConnection())
    let terminal = TerminalSession(connection: connection, modes: modes(for: options), keyboardProtocol: .probe)
    let frames = FrameBox()
    let renderer = try makeRenderer(on: connection, frames: frames)
    let shutdown = SignalShutdown(
        session: terminal, stopRendering: { renderer.halt() },
        onExit: { code in
            beforeSignalExit()
            exit(code)
        })
    let (resizes, resized) = AsyncStream<Void>.makeStream()
    let signals = SignalHandler(onResize: { resized.yield() }, onShutdown: { shutdown.handle($0) })
    try signals.start()
    defer { signals.stop() }
    // macOS posts appearance changes as a distributed notification; the screen asks the terminal for its colours again on each (0108).
    let (appearances, appearanceChanged) = AsyncStream<Void>.makeStream()
    let watcher = TerminalColours.follows(options) ? TerminalColours.watchAppearance { appearanceChanged.yield() } : nil
    defer { watcher.map(TerminalColours.stopWatching) }
    return try await runInteractiveScreen(
        on: ScreenTerminal(
            connection: connection, session: terminal, renderer: renderer, frames: frames,
            clipboard: ScreenClipboard(
                connection: connection, environment: ProcessInfo.processInfo.environment,
                pasteboard: HostPasteboard.write, read: HostPasteboard.read)),
        conversation: conversation, label: label, options: options,
        opening: openingUpdates(history: history, notices: notices, details: details),
        changes: (resizes, appearances))
}

/// The screen over an injected connection, so every exit path is drivable from a test.
@discardableResult
func runInteractiveScreen(
    on connection: any TerminalConnection, conversation: any Conversation, label: String,
    history: [ConversationUpdate] = [], notices: [String] = [], details: [String] = [],
    options: ScreenOptions = ScreenOptions(), environment: [String: String] = [:],
    pasteboard: @escaping @Sendable (String) async -> PasteboardResult = { _ in .copied },
    resizes: AsyncStream<Void>, appearances: AsyncStream<Void> = AsyncStream { $0.finish() }
) async throws -> ScreenExit {
    let connection = SerializedConnection(connection)
    let terminal = TerminalSession(connection: connection, modes: modes(for: options), keyboardProtocol: .probe)
    let frames = FrameBox()
    return try await runInteractiveScreen(
        on: ScreenTerminal(
            connection: connection, session: terminal, renderer: try makeRenderer(on: connection, frames: frames),
            frames: frames,
            clipboard: ScreenClipboard(connection: connection, environment: environment, pasteboard: pasteboard)),
        conversation: conversation, label: label, options: options,
        opening: openingUpdates(history: history, notices: notices, details: details),
        changes: (resizes, appearances))
}

/// The screen inside a terminal session: TerminalKit enters its modes (alternate screen, hidden cursor,
/// bracketed paste, and disambiguated keys when the terminal answers the keyboard probe) in one write and
/// leaves them on every exit path (TerminalKit ADR-0019, ADR-0020).
///
/// The last frame is drawn before the terminal is restored, on a normal exit and on an error.
private func runInteractiveScreen(
    on screen: ScreenTerminal, conversation: any Conversation, label: String, options: ScreenOptions,
    opening: [ConversationUpdate], changes: (resizes: AsyncStream<Void>, appearances: AsyncStream<Void>)
) async throws -> ScreenExit {
    let exit: ScreenExit
    do {
        try screen.session.enter()
        let session = ScreenSession(
            screen, conversation: conversation, label: label, options: options, opening: opening)
        exit = try await session.run(resizes: changes.resizes, appearances: changes.appearances)
    } catch {
        await screen.renderer.finish()
        screen.session.leave()
        throw error
    }
    await screen.renderer.finish()
    screen.session.leave()
    return exit
}

/// What the screen shows before the first prompt: a resumed session's history, then the notices.
private func openingUpdates(history: [ConversationUpdate], notices: [String], details: [String]) -> [ConversationUpdate]
{
    history + notices.map { .notice($0, isError: false) } + details.map { .detail($0) }
}
