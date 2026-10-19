internal import Foundation
internal import TerminalKitCodecs
internal import TerminalKitCore
internal import TerminalKitIO
public import TerminalKitInput
internal import TerminalKitRender

/// Runs the interactive screen on the terminal until the user quits, then restores the terminal.
///
/// SIGINT and SIGTERM still restore the terminal (raw mode clears `ISIG`, so Ctrl-C arrives as a key and
/// means "abort the turn" or "quit"). SIGWINCH redraws at the new size.
@MainActor
public func runInteractiveScreen(conversation: any Conversation, label: String, notices: [String] = []) async throws {
    let connection = POSIXTerminalConnection()
    let shutdown = SignalShutdown(connection: connection) { code in exit(code) }
    let (resizes, resized) = AsyncStream<Void>.makeStream()
    let signals = SignalHandler(onResize: { resized.yield() }, onShutdown: { shutdown.handle($0) })
    try signals.start()
    defer { signals.stop() }
    try await runInteractiveScreen(
        on: connection, conversation: conversation, label: label, notices: notices, resizes: resizes)
}

/// The screen over an injected connection, so every exit path is drivable from a test. On the main actor,
/// where TerminalKit's render pipeline lives; the loop only awaits, it never blocks.
@MainActor
func runInteractiveScreen(
    on connection: any TerminalConnection, conversation: any Conversation, label: String, notices: [String] = [],
    resizes: AsyncStream<Void>
) async throws {
    try connection.enterRawMode()
    defer { TerminalTeardown.run(on: connection) }
    // Bracketed paste, so a pasted newline arrives inside the paste rather than as Enter. The reset ladder's first
    // tier turns it off again on every exit path.
    try connection.writeContiguous(
        ContiguousArray(
            EscapeSequences.enterAlternateScreen + EscapeSequences.hideCursor + EscapeSequences.clearScreen
                + EscapeSequences.enableBracketedPaste))
    let session = try ScreenSession(connection: connection, conversation: conversation, label: label, notices: notices)
    try await session.run(resizes: resizes)
}

/// One interactive screen: its state has a single owner, the loop over one merged event stream.
@MainActor
private final class ScreenSession {
    private let connection: any TerminalConnection
    private let conversation: any Conversation
    private let pipeline: RenderPipeline
    private var controller: ScreenController
    private var composer = ScreenComposer()
    private var run: Task<Void, Never>?
    private let events: AsyncStream<ScreenEvent>
    private let sink: AsyncStream<ScreenEvent>.Continuation

    init(connection: any TerminalConnection, conversation: any Conversation, label: String, notices: [String]) throws {
        let size = try connection.getSize()
        self.connection = connection
        self.conversation = conversation
        pipeline = RenderPipeline(connection: connection, columns: size.columns, rows: size.rows)
        controller = ScreenController(label: label)
        for notice in notices { controller.handle(.notice(notice, isError: false)) }
        (events, sink) = AsyncStream<ScreenEvent>.makeStream()
    }

    func run(resizes: AsyncStream<Void>) async throws {
        let input = InputSource(connection: connection)
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
        pipeline.beginFrame()
        let cursor = composer.compose(controller.state, into: &pipeline.buffer)
        (pipeline.cursorRow, pipeline.cursorCol) = (cursor.row, cursor.column)
        if full { try pipeline.forceRedraw() } else { try pipeline.flush() }
    }
}

/// Everything the screen's loop reacts to, merged into one stream so state has a single owner.
private enum ScreenEvent: Sendable {
    case input(InputEvent)
    case update(ConversationUpdate)
    case resize
    case inputEnded
}
