internal import TerminalKitRender
internal import TerminalKitStyle
internal import TerminalKitText

/// What the interactive screen shows.
public struct ScreenState: Sendable, Equatable {
    public var transcript = Transcript()
    public var editor = PromptEditor()
    /// The requested input height; layout also caps it to a third of the screen (ADR-0046).
    public var promptRows = ScreenOptions().promptRows
    /// Shown at the left of the status line, such as the model.
    public var label: String
    /// Whether a run is in progress: the status line says so and how to abort it.
    public var running = false
    /// Set by a command that wants the screen closed with this reason once its run has ended.
    public var exitRequest: ScreenExit?
    /// Shown at the right of the status line, such as token usage; empty for none.
    public var detail = ""
    /// What is running beside the conversation, newest list from the composition root.
    public var runners: [RunnerInfo] = []
    /// Whether the list of `runners` is open above the status line. It closes by itself when nothing is running.
    public var runnersOpen = false
    /// A question waiting for y, a or n: while it waits, those keys answer it and nothing is typed.
    public var pendingApproval: PendingApproval?
    /// The project's files for the `@` picker; nil until the first listing arrives (roadmap 0048).
    var files: ProjectFiles?
    /// When ``files`` arrived, so a listing that has aged is asked for again.
    var filesLoadedAt: ContinuousClock.Instant?
    /// Whether a listing was asked for and has not arrived.
    var filesLoading = false
    /// The skills for the `/` picker, as commands; nil until the first listing arrives (roadmap 0061).
    var skills: [SlashCommand]?
    /// Whether the skills were asked for. They are asked for once, when a command picker first opens, never at launch.
    var skillsRequested = false
    /// The picker for the word under the cursor: commands for a slash that starts the draft, files for an `@`; nil otherwise.
    var picker: CompletionPicker?
    /// Where the word the user closed the picker on starts. It stays closed until the cursor leaves that word.
    var pickerDismissedAt: Int?
    /// How many wrapped lines the transcript is scrolled up from the bottom.
    public var scrollback = 0
    /// What the user has selected with the pointer, anchored in the conversation so it survives scrolling and streaming.
    var selection: ContentSelection<Int>?
    /// What is selected in the draft, as character offsets, while a selection in the input exists.
    var inputSelection: Range<Int>?
    /// The display row of the draft the wheel put at the top of the input, or nil while the window follows the cursor.
    var promptScroll: Int?
    /// Feedback from the last copy request. It reports routing or failure, never an unconfirmed clipboard acknowledgement.
    var clipboardNotice = ""
    /// When Ctrl+C was pressed on an empty, idle input: the status line asks for a second press, which quits while the window lasts.
    var quitArmedAt: ContinuousClock.Instant?
    /// Names the native-selection bypass while mouse reporting is enabled (ADR-0046).
    var nativeSelectionHint = ""

    /// A screen with nothing in it yet.
    public init(label: String) { self.label = label }
}
