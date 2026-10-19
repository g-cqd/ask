internal import Foundation
internal import TerminalKitIO
public import TerminalKitInput
internal import TerminalKitRender

/// Runs the interactive screen on the terminal until the user quits, then restores the terminal.
///
/// SIGINT and SIGTERM still restore the terminal (raw mode clears `ISIG`, so Ctrl-C arrives as a key and
/// means "abort the turn" or "quit"). SIGWINCH redraws at the new size.
@MainActor
/// - Parameters:
///   - conversation: runs each submitted prompt.
///   - label: shown at the left of the status line.
///   - history: a resumed session's conversation, shown before anything else.
///   - notices: shown after the history, such as which instruction files apply.
/// - Throws: when the terminal cannot be set up.
public func runInteractiveScreen(
    conversation: any Conversation, label: String, history: [ConversationUpdate] = [], notices: [String] = []
) async throws {
    let connection = POSIXTerminalConnection()
    let terminal = TerminalSession(connection: connection, modes: .fullScreen, keyboardProtocol: .probe)
    let shutdown = SignalShutdown(session: terminal) { code in exit(code) }
    let (resizes, resized) = AsyncStream<Void>.makeStream()
    let signals = SignalHandler(onResize: { resized.yield() }, onShutdown: { shutdown.handle($0) })
    try signals.start()
    defer { signals.stop() }
    try await runInteractiveScreen(
        in: terminal, on: connection, conversation: conversation, label: label,
        opening: openingUpdates(history: history, notices: notices), resizes: resizes)
}

/// The screen over an injected connection, so every exit path is drivable from a test.
@MainActor
func runInteractiveScreen(
    on connection: any TerminalConnection, conversation: any Conversation, label: String,
    history: [ConversationUpdate] = [], notices: [String] = [], resizes: AsyncStream<Void>
) async throws {
    let terminal = TerminalSession(connection: connection, modes: .fullScreen, keyboardProtocol: .probe)
    try await runInteractiveScreen(
        in: terminal, on: connection, conversation: conversation, label: label,
        opening: openingUpdates(history: history, notices: notices), resizes: resizes)
}

/// The screen inside a terminal session: TerminalKit enters its modes (alternate screen, hidden cursor,
/// bracketed paste, and disambiguated keys when the terminal answers the keyboard probe) in one write and
/// leaves them on every exit path (TerminalKit ADR-0019, ADR-0020). On the main actor, where TerminalKit's
/// render pipeline lives; the loop only awaits, it never blocks.
@MainActor
private func runInteractiveScreen(
    in terminal: TerminalSession, on connection: any TerminalConnection, conversation: any Conversation,
    label: String, opening: [ConversationUpdate], resizes: AsyncStream<Void>
) async throws {
    try terminal.enter()
    defer { terminal.leave() }
    let session = try ScreenSession(
        terminal: terminal, connection: connection, conversation: conversation, label: label, opening: opening)
    try await session.run(resizes: resizes)
}

/// What the screen shows before the first prompt: a resumed session's history, then the notices.
private func openingUpdates(history: [ConversationUpdate], notices: [String]) -> [ConversationUpdate] {
    history + notices.map { .notice($0, isError: false) }
}

@MainActor
private final class ScreenSession {
    private let terminal: TerminalSession
    private let connection: any TerminalConnection
    private let input: InputSource
    private let conversation: any Conversation
    private let pipeline: RenderPipeline
    private var controller: ScreenController
    private var composer = ScreenComposer()
    private var run: Task<Void, Never>?
    private let events: AsyncStream<ScreenEvent>
    private let sink: AsyncStream<ScreenEvent>.Continuation

    init(
        terminal: TerminalSession, connection: any TerminalConnection, conversation: any Conversation, label: String,
        opening: [ConversationUpdate]
    ) throws {
        let size = try connection.getSize()
        self.terminal = terminal
        self.connection = connection
        input = InputSource(connection: connection, escapeIsUnambiguous: terminal.escapeIsUnambiguous)
        self.conversation = conversation
        pipeline = RenderPipeline(connection: connection, columns: size.columns, rows: size.rows)
        controller = ScreenController(label: label)
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
        try render(full: true)
        for await event in events {
            guard try await handle(event) else { return }
        }
    }

    /// Applies one event and renders. Returns false when the screen should close.
    private func handle(_ event: ScreenEvent) async throws -> Bool {
        var effects: [ScreenController.Effect] = []
        switch event {
            case .input(let inputEvent) where terminal.observe(inputEvent):
                // The terminal's answer to the keyboard probe, not a key. Here, between frames, so the flags it
                // pushes never land inside one.
                input.escapeIsUnambiguous = terminal.escapeIsUnambiguous
                return true
            case .input(let inputEvent):
                effects = controller.handle(inputEvent, pageRows: Swift.max(1, pipeline.rows - 3))
            case .update(let update):
                controller.handle(update)
                if update == .runEnded { run = nil }
            case .resize:
                if let size = try? connection.getSize() {
                    pipeline.resize(columns: size.columns, rows: size.rows)
                    try render(full: true)
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
                case .cancelRun:
                    run?.cancel()
                case .quit:
                    run?.cancel()
                    // A cancelled run stops its tools' processes before it ends; wait for that.
                    await run?.value
                    return false
            }
        }
        try render()
        return true
    }

    private func render(full: Bool = false) throws {
        try pipeline.draw(controller.state, with: &composer, full: full)
    }
}

/// Everything the screen's loop reacts to, merged into one stream so state has a single owner.
private enum ScreenEvent: Sendable {
    case input(InputEvent)
    case update(ConversationUpdate)
    case resize
    case inputEnded
}
