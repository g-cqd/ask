internal import Foundation
internal import TerminalKitIO
internal import TerminalKitInput
internal import TerminalKitRender

/// One open screen: the controller that owns its state, the render thread that draws it, and the loop that applies every event.
final class ScreenSession {
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
    private var columns: Int
    private var run: Task<Void, Never>?
    private var runnerOutput = RunnerOutputWatch()
    private var jobOutput: [String: Task<Void, Never>] = [:]
    /// Ticks while a drag is held at an edge, because a held button reports no motion.
    private var autoscroll = AutoscrollTimer()
    private var progress = BlockProgressTimer()
    private let events: AsyncStream<ScreenEvent>
    private let sink: AsyncStream<ScreenEvent>.Continuation
    private var exit = ScreenExit.quit
    /// The terminal's colours, when the tints follow them (`ui.appearance` auto); nil when they are fixed or off.
    private var colours: TerminalColours?

    init(
        _ screen: ScreenTerminal, conversation: any Conversation, label: String, options: ScreenOptions,
        opening: consuming [ConversationUpdate]
    ) {
        terminal = screen.session
        renderer = screen.renderer
        connection = screen.connection
        input = InputSource(connection: screen.connection, escapeIsUnambiguous: screen.session.escapeIsUnambiguous)
        self.conversation = conversation
        let size = try? screen.connection.getSize()
        rows = size?.rows ?? 24
        columns = Swift.max(1, size?.columns ?? 80)
        frames = screen.frames
        clipboard = screen.clipboard
        controller = ScreenController(label: label, commands: conversation.commands, options: options)
        controller.state.nativeSelectionHint = options.mouse ? screen.clipboard.nativeSelectionHint : ""
        controller.setScreenRows(rows)
        colours = TerminalColours(following: options, connection: screen.connection)
        for update in opening { controller.handle(update) }
        (events, sink) = AsyncStream<ScreenEvent>.makeStream()
    }

    func run(resizes: AsyncStream<Void>, appearances: AsyncStream<Void>) async throws -> ScreenExit {
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
        let recolouring = SystemAppearance.askAgain(after: appearances) { sink.yield(.askColours) }
        defer { recolouring.cancel() }
        colours?.ask()
        defer {
            forwarding.cancel()
            resizing.cancel()
            watching?.cancel()
            input.stop()
        }
        defer {
            autoscroll.stop()
            progress.stop()
            runnerOutput.stop()
            for task in jobOutput.values { task.cancel() }
        }
        render(full: true)
        for await event in events {
            if let taken = colours?.take(event) {
                if case .page(let page) = taken { controller.state.adopt(page) }
                render(full: true)
                continue
            }
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
                // A click means what was drawn, and a Page key scrolls through the rows drawn, so every input is resolved against
                // the newest frame: a key that came first after a resume met an empty one and PageUp did not move.
                controller.frame = frames.load()
                effects = controller.handle(inputEvent, pageRows: Swift.max(1, rows - 3), columns: columns)
            case .update(let update):
                effects = controller.handle(update)
                if case .jobOutput(let job) = update, job.status != .running { jobOutput[job.id] = nil }
                if update == .clearConversation {
                    for task in jobOutput.values { task.cancel() }
                    jobOutput.removeAll()
                }
                if update == .runEnded {
                    run = nil
                    if let requested = controller.state.exitRequest {
                        exit = requested
                        return false
                    }
                }
            case .progressTick:
                controller.advanceProgress()
            case .tick:
                controller.frame = frames.load()
                guard controller.tick() else {
                    syncAutoscroll()
                    return true
                }
            case .resize:
                if let size = try? connection.getSize() {
                    rows = size.rows
                    controller.setScreenRows(size.rows)
                    columns = Swift.max(1, size.columns)
                    renderer.resize(columns: size.columns, rows: size.rows)
                    render(full: true)
                    return true
                }
            case .copied(let notice, let failed, let generation):
                controller.finishCopy(notice, failed: failed, generation: generation)
            case .pasteRefused(let reason):
                controller.state.transcript.addNotice(reason, isError: true)
            case .quitWindowEnded(let generation):
                controller.quitWindowEnded(generation: generation)
            case .sandboxNoteEnded(let generation): controller.sandboxNoteEnded(generation: generation)
            case .inputEnded:
                effects = [.quit]
            case .askColours:
                return true
        }
        for effect in effects where await !perform(effect) {
            return false
        }
        progress.update(wanted: controller.hasLiveProgress) { [sink] in sink.yield(.progressTick) }
        runnerOutput.sync(lane: controller.state.lane?.id)
        syncAutoscroll()
        render()
        return true
    }

    /// Carries out one effect of the controller. Returns false when the screen should close.
    private func perform(_ effect: ScreenController.Effect) async -> Bool {
        let sink = sink
        switch effect {
            case .startRun(let prompt):
                run = conversation.start(prompt) { sink.yield(.update($0)) }
            case .queuePrompt(let id, let text, let followUp):
                conversation.enqueue(text, id: id, followUp: followUp)
            case .runCommand(let name, let arguments):
                run = conversation.command(name, arguments: arguments) { sink.yield(.update($0)) }
            case .answerApproval(let id, let choice): conversation.answer(approval: id, with: choice)
            case .answerQuestions(let id, let answers): conversation.answer(questions: id, with: answers)
            case .indexFiles:
                let conversation = conversation
                Task { sink.yield(.update(.files(await conversation.projectFiles()))) }
            case .armQuitTimer(let generation):
                ScreenTimer.after(ScreenController.quitWindow, send: .quitWindowEnded(generation: generation), to: sink)
            case .armSandboxNoteTimer(let generation):
                ScreenTimer.after(
                    ScreenController.sandboxNoteWindow, send: .sandboxNoteEnded(generation: generation), to: sink)
            case .readRunnerOutput(let id):
                runnerOutput.watch(id, in: conversation, sink: sink)
            case .watchJob(let id):
                jobOutput[id]?.cancel()
                jobOutput[id] = conversation.watchJob(id) { sink.yield(.update(.jobOutput($0))) }
            case .listSkills:
                let conversation = conversation
                Task { sink.yield(.update(.skills(await conversation.skillCommands()))) }
            case .listChoices(let command):
                let conversation = conversation
                Task { sink.yield(.update(.choices(command: command, rows: await conversation.choices(for: command)))) }
            case .commitConfig(let scope, let path, let value):
                await conversation.commitConfig(scope: scope, path: path, value: value) { sink.yield(.update($0)) }
            case .answerInput(let id, let text):
                conversation.answer(input: id, with: text)
            case .cancelRun:
                run?.cancel()
            case .pasteFromClipboard:
                clipboard.paste(into: sink)
            case .copy(let text):
                let generation = controller.beginCopy()
                controller.state.clipboardNotice = clipboard.copy(text) {
                    sink.yield(.copied(notice: $0, failed: $1, generation: generation))
                }
            case .openLink(let uri):
                if let notice = LinkOpener.perform(uri) { controller.state.clipboardNotice = notice }
            case .quit:
                run?.cancel()
                // A cancelled run stops its tools' processes before it ends; wait for that.
                await run?.value
                return false
        }
        return true
    }

    private func syncAutoscroll() {
        let sink = sink
        autoscroll.update(wanted: controller.isAutoscrolling) { sink.yield(.tick) }
    }

    /// Hands the render thread the screen as it is now. It draws the newest state it finds, so a burst of events is
    /// one frame, and this never waits for one.
    private func render(full: Bool = false) {
        if full { renderer.redraw() }
        renderer.submit(controller.state)
    }
}
