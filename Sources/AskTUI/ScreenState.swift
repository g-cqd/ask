internal import TerminalKitRender
internal import TerminalKitStyle
internal import TerminalKitText

/// What the interactive screen shows.
public struct ScreenState: Sendable, Equatable {
    public var transcript = Transcript()
    public var editor = PromptEditor()
    /// Shown at the left of the status line, such as the model.
    public var label: String
    /// Whether a run is in progress: the status line says so and how to abort it.
    public var running = false
    /// Set by a command that wants the screen closed with this reason once its run has ended.
    public var exitRequest: ScreenExit?
    /// Shown at the right of the status line, such as token usage; empty for none.
    public var detail = ""
    /// How many wrapped lines the transcript is scrolled up from the bottom.
    public var scrollback = 0

    /// A screen with nothing in it yet.
    public init(label: String) { self.label = label }
}
