internal import TerminalKitCodecs
public import TerminalKitInput

/// What a running conversation tells the screen. The composition root maps agent events onto these.
public enum ConversationUpdate: Sendable, Equatable {
    case assistantText(String)
    case toolStarted(name: String, summary: String)
    case toolFinished(Transcript.ToolStatus)
    case notice(String, isError: Bool)
    /// The run is over, however it ended.
    case runEnded
}

/// Starts runs for the screen. Implemented by the composition root over the agent loop, so AskTUI never
/// imports the agent (ADR-0009).
public protocol Conversation: Sendable {
    /// Starts a run for `prompt`. Updates arrive through `update`, ending with ``ConversationUpdate/runEnded``.
    /// - Returns: the run's task; cancelling it aborts the run.
    func start(_ prompt: String, update: @escaping @Sendable (ConversationUpdate) -> Void) -> Task<Void, Never>
}

/// The screen's behaviour as a pure state machine: events in, state and effects out. The driver performs the
/// effects; tests drive this directly.
public struct ScreenController: Sendable {
    /// Something the driver must do.
    public enum Effect: Sendable, Equatable {
        case startRun(String)
        case cancelRun
        case quit
    }

    public private(set) var state: ScreenState

    /// A controller showing `label` in the status line.
    public init(label: String) { state = ScreenState(label: label) }

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
    public mutating func handle(_ update: ConversationUpdate) {
        switch update {
            case .assistantText(let text): state.transcript.addAssistantText(text)
            case .toolStarted(let name, let summary): state.transcript.startTool(name: name, summary: summary)
            case .toolFinished(let status): state.transcript.finishTool(status)
            case .notice(let text, let isError): state.transcript.addNotice(text, isError: isError)
            case .runEnded: state.running = false
        }
    }

    private mutating func edit(_ key: KeyEvent) -> [Effect] {
        switch state.editor.apply(key) {
            case .submitted(let prompt):
                guard !state.running else {
                    state.transcript.addNotice("A turn is still running; press Esc to abort it first.", isError: false)
                    return []
                }
                state.transcript.addUser(prompt)
                state.running = true
                state.scrollback = 0
                return [.startRun(prompt)]
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

    private mutating func abort() -> [Effect] {
        state.transcript.addNotice("Aborting…", isError: false)
        return [.cancelRun]
    }
}
