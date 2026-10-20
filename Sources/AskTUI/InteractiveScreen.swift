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
///   - options: how the pointer behaves: whether it is reported, whether a selection is copied, how far the wheel scrolls.
///   - beforeSignalExit: runs when a shutdown signal is about to end the process, after the terminal is
///     restored: the last chance to stop child processes.
/// - Returns: why the screen closed.
/// - Throws: when the terminal cannot be set up.
@discardableResult
public func runInteractiveScreen(
    conversation: any Conversation, label: String, history: [ConversationUpdate] = [], notices: [String] = [],
    options: ScreenOptions = ScreenOptions(), beforeSignalExit: @escaping @Sendable () -> Void = {}
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
    return try await runInteractiveScreen(
        on: ScreenTerminal(
            connection: connection, session: terminal, renderer: renderer, frames: frames,
            clipboard: ScreenClipboard(
                connection: connection, environment: ProcessInfo.processInfo.environment,
                pasteboard: ScreenClipboard.pbcopy)),
        conversation: conversation, label: label, options: options,
        opening: openingUpdates(history: history, notices: notices), resizes: resizes)
}

/// The screen over an injected connection, so every exit path is drivable from a test.
@discardableResult
func runInteractiveScreen(
    on connection: any TerminalConnection, conversation: any Conversation, label: String,
    history: [ConversationUpdate] = [], notices: [String] = [], options: ScreenOptions = ScreenOptions(),
    environment: [String: String] = [:], pasteboard: @escaping @Sendable (String) -> Void = { _ in },
    resizes: AsyncStream<Void>
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
        opening: openingUpdates(history: history, notices: notices), resizes: resizes)
}

/// The screen inside a terminal session: TerminalKit enters its modes (alternate screen, hidden cursor,
/// bracketed paste, and disambiguated keys when the terminal answers the keyboard probe) in one write and
/// leaves them on every exit path (TerminalKit ADR-0019, ADR-0020).
///
/// The last frame is drawn before the terminal is restored, on a normal exit and on an error.
private func runInteractiveScreen(
    on screen: ScreenTerminal, conversation: any Conversation, label: String, options: ScreenOptions,
    opening: [ConversationUpdate], resizes: AsyncStream<Void>
) async throws -> ScreenExit {
    let exit: ScreenExit
    do {
        try screen.session.enter()
        let session = ScreenSession(
            screen, conversation: conversation, label: label, options: options, opening: opening)
        exit = try await session.run(resizes: resizes)
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
    private let frames: FrameBox
    private var clipboard: ScreenClipboard
    /// The screen's height, for paging; the render loop knows its own.
    private var rows: Int
    private var run: Task<Void, Never>?
    private let events: AsyncStream<ScreenEvent>
    private let sink: AsyncStream<ScreenEvent>.Continuation
    private var exit = ScreenExit.quit

    fileprivate init(
        _ screen: ScreenTerminal, conversation: any Conversation, label: String, options: ScreenOptions,
        opening: [ConversationUpdate]
    ) {
        terminal = screen.session
        renderer = screen.renderer
        connection = screen.connection
        input = InputSource(connection: screen.connection, escapeIsUnambiguous: screen.session.escapeIsUnambiguous)
        self.conversation = conversation
        rows = (try? screen.connection.getSize().rows) ?? 24
        frames = screen.frames
        clipboard = screen.clipboard
        controller = ScreenController(label: label, commands: conversation.commands, options: options)
        for update in opening { controller.handle(update) }
        (events, sink) = AsyncStream<ScreenEvent>.makeStream()
    }

    func run(resizes: AsyncStream<Void>) async throws -> ScreenExit {
        let input = input
        let sink = sink
        let forwarding = Task {
            for await event in input.events { sink.yield(.input(event)) }
            sink.yield(.inputEnded)
        }
        let resizing = Task {
            for await _ in resizes { sink.yield(.resize) }
        }
        let watching = conversation.background { sink.yield(.update($0)) }
        input.start()
        defer {
            forwarding.cancel()
            resizing.cancel()
            watching?.cancel()
            input.stop()
        }
        render(full: true)
        for await event in events {
            guard await handle(event) else { return exit }
        }
        return exit
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
                // A click means what was drawn, so it is resolved against the newest frame.
                if case .mouse = inputEvent { controller.frame = frames.load() }
                effects = controller.handle(inputEvent, pageRows: Swift.max(1, rows - 3))
            case .update(let update):
                effects = controller.handle(update)
                if update == .runEnded {
                    run = nil
                    if let requested = controller.state.exitRequest {
                        exit = requested
                        return false
                    }
                }
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
                case .queuePrompt(let id, let text, let followUp):
                    conversation.enqueue(text, id: id, followUp: followUp)
                case .runCommand(let name, let arguments):
                    let sink = sink
                    run = conversation.command(name, arguments: arguments) { sink.yield(.update($0)) }
                case .cancelRun:
                    run?.cancel()
                case .copy(let text):
                    clipboard.copy(text)
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
