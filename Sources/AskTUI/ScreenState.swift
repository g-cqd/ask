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
    /// The same label at shorter lengths, longest first, for a narrow status line; empty when there is only the one.
    public var labelVariants: [String] = []
    /// Whether a run is in progress: the status line says so and how to abort it.
    public var running = false
    /// Set by a command that wants the screen closed with this reason once its run has ended.
    public var exitRequest: ScreenExit?
    /// Shown at the right of the status line, such as token usage; empty for none.
    public var detail = ""
    /// The newest runner snapshot. Its cached preorder and counts feed every view.
    public private(set) var runnerTree = RunnerTree()
    /// Updating the runners rebuilds the tree once, not once per frame.
    public var runners: [RunnerInfo] {
        get { runnerTree.runners }
        set { runnerTree = RunnerTree(newValue) }
    }
    /// Whether the runner strip is open below the input. It closes by itself when no runners remain.
    public var runnersOpen = false
    /// The runner whose output the transcript shows, while one is focused; the main conversation waits inside it (roadmap 0062).
    var lane: LaneView?
    /// How many lanes were opened, so each one's transcript has revisions of its own.
    var laneSerial = 0
    /// The strip row the keys act on, by runner id, while the strip has the keys; nil while the input does.
    var stripSelection: String?
    /// Whether the runner sidebar is open: the same tree as the strip, beside the transcript when the screen is wide enough.
    var sidebarOpen = false
    /// The runners whose children are hidden in the strip.
    var collapsedRunners: Set<String> = []
    /// A question waiting for y, a or n: while it waits, those keys answer it and nothing is typed.
    public var pendingApproval: PendingApproval?
    /// A line a running command asked for, while it waits: the keys go to ``inputAnswer`` until Enter or Esc.
    public var pendingInput: PendingInput?
    /// What is typed for ``pendingInput``; never drawn but as dots when the input is a secret.
    var inputAnswer = PromptEditor()
    /// Each command's list of choices, as the conversation last offered it, and when it was asked for.
    var choices: [String: ChoiceList] = [:]
    /// Whether details are shown, and the ones held back until `/verbose` asks for them.
    public var verbose = false
    var heldDetails: [String] = []
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

    /// What the input starts with, and whether the screen is tinted and ruled: from the options, which decide the look (roadmap 0074).
    public var promptPrefix = ""
    public var theme = ScreenTheme()
    public var separator = true

    /// A screen with nothing in it yet.
    public init(label: String, options: ScreenOptions = ScreenOptions()) {
        self.label = label
        promptPrefix = options.prompt
        separator = options.separator
        theme = ScreenTheme(tinted: options.tint, light: options.lightBackground)
    }
}
