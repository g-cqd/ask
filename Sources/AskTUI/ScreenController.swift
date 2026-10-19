internal import TerminalKitCodecs
public import TerminalKitInput

/// The screen's behaviour as a pure state machine: events in, state and effects out. The driver performs the
/// effects; tests drive this directly.
public struct ScreenController: Sendable {
    /// Something the driver must do.
    public enum Effect: Sendable, Equatable {
        case startRun(String)
        case queuePrompt(id: Int, text: String, followUp: Bool)
        case runCommand(name: String, arguments: String)
        case cancelRun
        case quit
    }

    public internal(set) var state: ScreenState
    /// The commands the screen answers itself (`/help`, `/quit`) and those the conversation runs.
    private let commands: [SlashCommand]
    var pending: [Pending] = []
    var nextPromptID = 0
    var acceptsInput = false
    var returningInput = false

    /// What `/help` and `/quit` are, always present.
    static let builtIn = [
        SlashCommand(name: "help", summary: "List commands. While busy: Enter steers; Alt+Enter queues a follow-up."),
        SlashCommand(name: "quit", summary: "Leave ask, stopping a running turn first."),
        SlashCommand(name: "follow-up", summary: "Queue a message after the agent finishes: /follow-up TEXT.")
    ]

    /// A controller showing `label` in the status line, answering `commands` besides the built-in ones.
    public init(label: String, commands: [SlashCommand] = []) {
        state = ScreenState(label: label)
        self.commands = Self.builtIn + commands
    }

    /// Applies terminal input. `pageRows` is how far Page Up and Page Down scroll.
    public mutating func handle(_ event: InputEvent, pageRows: Int) -> [Effect] {
        switch event {
            case .key(let key):
                if key.keyCode == Key.pageUp.rawValue {
                    state.scrollback += Swift.max(1, pageRows)
                    return []
                }
                if key.keyCode == Key.pageDown.rawValue {
                    state.scrollback = Swift.max(0, state.scrollback - Swift.max(1, pageRows))
                    return []
                }
                return edit(key)
            case .paste(let text):
                state.editor.paste(text)
                return []
            default:
                return []
        }
    }

    /// Applies an update from the running conversation.
    @discardableResult
    public mutating func handle(_ update: ConversationUpdate) -> [Effect] {
        switch update {
            case .userPrompt(let text): state.transcript.addUser(text)
            case .assistantText(let text): state.transcript.addAssistantText(text)
            case .toolStarted(let name, let summary): state.transcript.startTool(name: name, summary: summary)
            case .toolFinished(let status): state.transcript.finishTool(status)
            case .notice(let text, let isError): state.transcript.addNotice(text, isError: isError)
            case .requestExit(let exit): state.exitRequest = exit
            case .label(let text): state.label = text
            case .status(let text): state.detail = text
            case .promptAccepted(let id, let text):
                pending.removeAll { $0.id == id }
                state.transcript.addUser(text)
            case .returnQueuedPrompts: returningInput = true
            case .runEnded: return endRun()
        }
        return []
    }

    private mutating func edit(_ key: KeyEvent) -> [Effect] {
        switch state.editor.apply(key) {
            case .submitted(let line):
                return submit(line, followUp: key.modifiers.contains(.alt))
            case .escape:
                return state.running ? abort() : []
            case .interrupt:
                return state.running ? abort() : [.quit]
            case .endOfInput:
                return state.running ? [] : [.quit]
            case .edited, .ignored:
                return []
        }
    }

    /// A submitted line: a prompt, a command, or a command that does not exist.
    private mutating func submit(_ line: String, followUp: Bool) -> [Effect] {
        switch SlashInput(line) {
            case .prompt(let text):
                return submitPrompt(text, followUp: followUp)
            case .command(let name, let arguments):
                state.transcript.addUser(line)
                guard let command = commands.first(where: { $0.name == name }) else {
                    state.transcript.addNotice("There is no command /\(name); /help lists them.", isError: true)
                    return []
                }
                switch command.name {
                    case "help":
                        for entry in commands {
                            state.transcript.addNotice("/\(entry.name)  \(entry.summary)", isError: false)
                        }
                        return []
                    case "quit": return [.quit]
                    case "follow-up": return submitPrompt(arguments, followUp: true)
                    default:
                        guard !busy() else { return [] }
                        return begin(.runCommand(name: name, arguments: arguments))
                }
        }
    }

    /// Says so, and returns true, when a turn is still running.
    private mutating func busy() -> Bool {
        guard state.running else { return false }
        state.transcript.addNotice("A turn is still running; press Esc to abort it first.", isError: false)
        return true
    }

    mutating func begin(_ effect: Effect) -> [Effect] {
        if case .startRun = effect { acceptsInput = true } else { acceptsInput = false }
        returningInput = false
        state.running = true
        state.scrollback = 0
        return [effect]
    }

    private mutating func abort() -> [Effect] {
        returningInput = true
        state.transcript.addNotice("Aborting…", isError: false)
        return [.cancelRun]
    }
}
