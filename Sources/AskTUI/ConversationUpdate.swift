internal import TerminalKitCodecs
internal import TerminalKitInput

/// What a running conversation tells the screen. The composition root maps agent events onto these.
public enum ConversationUpdate: Sendable, Equatable {
    case assistantText(String)
    case toolStarted(name: String, summary: String)
    case toolFinished(Transcript.ToolStatus)
    case notice(String, isError: Bool)
    /// A short status for the status line, such as token usage.
    case status(String)
    /// The run is over, however it ended.
    case runEnded
}
