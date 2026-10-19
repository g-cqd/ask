internal import TerminalKitCodecs
internal import TerminalKitInput

/// What a running conversation tells the screen. The composition root maps agent events onto these.
public enum ConversationUpdate: Sendable, Equatable {
    /// A prompt the user wrote earlier, shown when a recorded session is resumed.
    case userPrompt(String)
    case assistantText(String)
    case toolStarted(name: String, summary: String)
    case toolFinished(Transcript.ToolStatus)
    case notice(String, isError: Bool)
    /// The left of the status line, such as the model, when it changes.
    case label(String)
    /// A short status for the status line, such as token usage.
    case status(String)
    /// Close the screen once the run that sent this has ended, so the caller can act on `exit`.
    case requestExit(ScreenExit)
    /// The run is over, however it ended.
    case runEnded
}
