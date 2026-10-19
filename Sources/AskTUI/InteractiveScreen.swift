internal import Foundation
internal import TerminalKitIO
public import TerminalKitInput
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
///   - notices: shown after the history, such as which instruction files apply.
///   - beforeSignalExit: runs when a shutdown signal is about to end the process, after the terminal is
///     restored: the last chance to stop child processes.
/// - Throws: when the terminal cannot be set up.
public func runInteractiveScreen(
    conversation: any Conversation, label: String, history: [ConversationUpdate] = [], notices: [String] = [],
    beforeSignalExit: @escaping @Sendable () -> Void = {}
) async throws {
    // Frames and the session's own escape sequences share one terminal, so their writes take turns.
    let connection = SerializedConnection(POSIXTerminalConnection())
    let terminal = TerminalSession(connection: connection, modes: .fullScreen, keyboardProtocol: .probe)
    let renderer = try makeRenderer(on: connection)
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
    try await runInteractiveScreen(
        on: ScreenTerminal(connection: connection, session: terminal, renderer: renderer),
        conversation: conversation, label: label, opening: openingUpdates(history: history, notices: notices),
        resizes: resizes)
}

/// What the screen draws on and with: the terminal, its mode session, and the thread that draws frames.
private struct ScreenTerminal {
    let connection: any TerminalConnection
    let session: TerminalSession
    let renderer: RenderLoop<ScreenComposer>
}

/// The screen over an injected connection, so every exit path is drivable from a test.
func runInteractiveScreen(
    on connection: any TerminalConnection, conversation: any Conversation, label: String,
    history: [ConversationUpdate] = [], notices: [String] = [], resizes: AsyncStream<Void>
) async throws {
    let connection = SerializedConnection(connection)
    let terminal = TerminalSession(connection: connection, modes: .fullScreen, keyboardProtocol: .probe)
    try await runInteractiveScreen(
        on: ScreenTerminal(connection: connection, session: terminal, renderer: try makeRenderer(on: connection)),
        conversation: conversation, label: label, opening: openingUpdates(history: history, notices: notices),
        resizes: resizes)
}

/// A render loop drawing the screen at the terminal's size. It idles until the first state is submitted.
private func makeRenderer(on connection: any TerminalConnection) throws -> RenderLoop<ScreenComposer> {
    let size = try connection.getSize()
    return RenderLoop(connection: connection, columns: size.columns, rows: size.rows, composer: ScreenComposer())
}

/// The screen inside a terminal session: TerminalKit enters its modes (alternate screen, hidden cursor,
/// bracketed paste, and disambiguated keys when the terminal answers the keyboard probe) in one write and
/// leaves them on every exit path (TerminalKit ADR-0019, ADR-0020).
///
/// The last frame is drawn before the terminal is restored, on a normal exit and on an error.
private func runInteractiveScreen(
    on screen: ScreenTerminal, conversation: any Conversation, label: String, opening: [ConversationUpdate],
    resizes: AsyncStream<Void>
) async throws {
    do {
        try screen.session.enter()
        let session = ScreenSession(screen, conversation: conversation, label: label, opening: opening)
        try await session.run(resizes: resizes)
    } catch {
        await screen.renderer.finish()
        screen.session.leave()
        throw error
    }
    await screen.renderer.finish()
    screen.session.leave()
}

/// What the screen shows before the first prompt: a resumed session's history, then the notices.
private func openingUpdates(history: [ConversationUpdate], notices: [String]) -> [ConversationUpdate] {
    history + notices.map { .notice($0, isError: false) }
}

private final class ScreenSession {
    private let terminal: TerminalSession
    private let renderer: RenderLoop<ScreenComposer>
    private let connection: any TerminalConnection
    private let input: InputSource
    private let conversation: any Conversation
    private var controller: ScreenController
    /// The screen's height, for paging; the render loop knows its own.
    private var rows: Int
    private var run: Task<Void, Never>?
    private let events: AsyncStream<ScreenEvent>
    private let sink: AsyncStream<ScreenEvent>.Continuation

    fileprivate init(
        _ screen: ScreenTerminal, conversation: any Conversation, label: String, opening: [ConversationUpdate]
    ) {
        terminal = screen.session
        renderer = screen.renderer
        connection = screen.connection
        input = InputSource(connection: screen.connection, escapeIsUnambiguous: screen.session.escapeIsUnambiguous)
        self.conversation = conversation
        rows = (try? screen.connection.getSize().rows) ?? 24
        controller = ScreenController(label: label, commands: conversation.commands)
        for update in opening { controller.handle(update) }
        (events, sink) = AsyncStream<ScreenEvent>.makeStream()
    }

    func run(resizes: AsyncStream<Void>) async throws {
        let input = input
        let sink = sink
        let forwarding = Task {
            for await event in input.events { sink.yield(.input(event)) }
            sink.yield(.inputEnded)
        }
        let resizing = Task {
            for await _ in resizes { sink.yield(.resize) }
        }
        input.start()
        defer {
            forwarding.cancel()
            resizing.cancel()
            input.stop()
        }
        render(full: true)
        for await event in events {
            guard await handle(event) else { return }
        }
    }

    /// Applies one event and renders. Returns false when the screen should close.
    private func handle(_ event: ScreenEvent) async -> Bool {
        var effects: [ScreenController.Effect] = []
        switch event {
            case .input(let inputEvent) where terminal.observe(inputEvent):
                // The terminal's answer to the keyboard probe, not a key. Here, between frames, so the flags it
                // pushes never land inside one.
                input.escapeIsUnambiguous = terminal.escapeIsUnambiguous
                return true
            case .input(let inputEvent):
                effects = controller.handle(inputEvent, pageRows: Swift.max(1, rows - 3))
            case .update(let update):
                controller.handle(update)
                if update == .runEnded { run = nil }
            case .resize:
                if let size = try? connection.getSize() {
                    rows = size.rows
                    renderer.resize(columns: size.columns, rows: size.rows)
                    render(full: true)
                    return true
                }
            case .inputEnded:
                effects = [.quit]
        }
        for effect in effects {
            switch effect {
                case .startRun(let prompt):
                    let sink = sink
                    run = conversation.start(prompt) { sink.yield(.update($0)) }
                case .runCommand(let name, let arguments):
                    let sink = sink
                    run = conversation.command(name, arguments: arguments) { sink.yield(.update($0)) }
                case .cancelRun:
                    run?.cancel()
                case .quit:
                    run?.cancel()
                    // A cancelled run stops its tools' processes before it ends; wait for that.
                    await run?.value
                    return false
            }
        }
        render()
        return true
    }

    /// Hands the render thread the screen as it is now. It draws the newest state it finds, so a burst of events is
    /// one frame, and this never waits for one.
    private func render(full: Bool = false) {
        if full { renderer.redraw() }
        renderer.submit(controller.state)
    }
}

/// Everything the screen's loop reacts to, merged into one stream so state has a single owner.
private enum ScreenEvent: Sendable {
    case input(InputEvent)
    case update(ConversationUpdate)
    case resize
    case inputEnded
}
