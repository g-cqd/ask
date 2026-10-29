/// How the screen treats the pointer. The defaults are ADR-0046's; the composition root fills them from `ui.*` configuration.
public struct ScreenOptions: Sendable, Equatable {
    /// Whether the terminal reports the mouse to ask. Off leaves the terminal's own selection and wheel alone.
    public var mouse: Bool
    /// Whether a finished selection is copied at once. Off keeps it highlighted and does not copy it.
    public var copyOnSelect: Bool
    /// Whether a tool's output starts folded to one line (ADR-0046: `ui.tools`). A click or Ctrl+O opens it.
    public var foldTools: Bool
    /// Whether the model's reasoning starts folded to one line (ADR-0046: `ui.thinking`). A click or Ctrl+T opens it.
    public var foldThinking: Bool
    /// How many lines one wheel step scrolls. Terminals send different numbers of steps for one gesture (TerminalKit ADR-0028).
    public var scrollLines: Int
    /// The most display rows the input may take, also capped to a third of the terminal (ADR-0046).
    public var promptRows: Int
    /// Whether a long code block starts folded to one line (`ui.code`). A click or Ctrl+G opens it.
    public var foldCode: Bool
    /// A code block with more lines than this is long (ADR-0046: `ui.codeFoldLines`); the screen also caps it at half its height.
    public var codeFoldLines: Int
    /// Whether the assistant's messages are drawn as Markdown (`ui.markdown`, roadmap 0065): headings, emphasis, lists, tables and links
    /// rather than the marks that make them. A selection still copies what the model wrote.
    public var markdown: Bool
    /// Whether the runner sidebar starts open (`ui.sidebar`). Ctrl+\ and `/sidebar` toggle it; it needs 70 columns.
    public var sidebar: Bool
    /// Whether details are shown: what ask did on its own account, such as the sandbox in force or a build that appeared (`--verbose`).
    /// `/verbose` toggles it, and shows what was held back meanwhile (ADR-0119).
    public var verbose: Bool
    /// What the input starts with (`ui.prompt`); none by default, since the input is marked by its tint (roadmap 0074).
    public var prompt: String
    /// Whether the input and the tool and user blocks have a tinted background (`ui.tint`).
    public var tint: Bool
    /// Whether a rule separates the conversation from the input (`ui.separator`).
    public var separator: Bool
    /// Whether each block has a row of padding around it (`ui.padding`).
    public var padding: Bool
    /// Whether the terminal's background is light, which picks the lighter tints; the composition root reads it from the environment.
    /// With ``appearance`` on auto it is only the first guess, until the terminal says what its colours are.
    public var lightBackground: Bool
    /// Where the tints come from (`ui.appearance`): the terminal's own colours, followed while ask runs, or a fixed light or dark page.
    public var appearance = ScreenAppearance.auto
    /// The home folder, which ask's own messages write as `~` (roadmap 0128); nil leaves paths as they are.
    public var home: String?
    /// Locale-aware elapsed units (`ui.localizedDurations`); off uses a compact clock.
    public var localizedDurations: Bool
    /// Which spinner style is used for progress and status indicators (`ui.spinner`).
    public var spinner: SpinnerStyle
    /// Whether leaving a focused job lane automatically returns to main when the job ends (`ui.jobAutoReturnWhenFocused`).
    public var jobAutoReturnWhenFocused: Bool
    /// Whether aborting a turn requires two-press Ctrl+C confirmation (`ui.abortTurnRequiresConfirmation`).
    public var abortTurnRequiresConfirmation: Bool
    /// Which keys interrupt a running turn (`ui.interruptKeys`).
    public var interruptKeys: InterruptKeys
    /// Whether Esc must be pressed twice to interrupt (`ui.escapeInterruptRequiresConfirmation`).
    public var escapeInterruptRequiresConfirmation: Bool
    /// What happens to queued messages after an interruption (`ui.interruptSendsQueued`).
    public var interruptSendsQueued: QueuedAfterInterrupt
    /// When a command's timeout is written in its header (`ui.timeout`).
    public var timeoutDisplay = TimeoutDisplay.auto
    /// The word in front of a command's timeout (`ui.timeoutLabel`), drawn in at most 8 cells.
    public var timeoutLabel = "timeout"

    /// The look before roadmap 0074: an `ask> ` prefix, no tint, no rule. What the screen's older tests were written against.
    public static let legacy = ScreenOptions(prompt: "ask> ", tint: false, separator: false, padding: false)

    public init(
        mouse: Bool = true, copyOnSelect: Bool = true, foldTools: Bool = true, foldThinking: Bool = true,
        scrollLines: Int = 3, promptRows: Int = 6, foldCode: Bool = true, codeFoldLines: Int = 20,
        markdown: Bool = true, sidebar: Bool = false, verbose: Bool = false, prompt: String = "", tint: Bool = true,
        separator: Bool = true,
        padding: Bool = true, lightBackground: Bool = false, localizedDurations: Bool = true,
        spinner: SpinnerStyle = .line, jobAutoReturnWhenFocused: Bool = true,
        abortTurnRequiresConfirmation: Bool = false, interruptKeys: InterruptKeys = .both,
        escapeInterruptRequiresConfirmation: Bool = true, interruptSendsQueued: QueuedAfterInterrupt = .all
    ) {
        self.mouse = mouse
        self.copyOnSelect = copyOnSelect
        self.foldTools = foldTools
        self.foldThinking = foldThinking
        self.scrollLines = Swift.max(1, scrollLines)
        self.promptRows = Swift.max(1, promptRows)
        self.foldCode = foldCode
        self.codeFoldLines = Swift.max(1, codeFoldLines)
        self.markdown = markdown
        self.sidebar = sidebar
        self.verbose = verbose
        self.prompt = prompt
        self.tint = tint
        self.separator = separator
        self.padding = padding
        self.lightBackground = lightBackground
        self.localizedDurations = localizedDurations
        self.spinner = spinner
        self.jobAutoReturnWhenFocused = jobAutoReturnWhenFocused
        self.abortTurnRequiresConfirmation = abortTurnRequiresConfirmation
        self.interruptKeys = interruptKeys
        self.escapeInterruptRequiresConfirmation = escapeInterruptRequiresConfirmation
        self.interruptSendsQueued = interruptSendsQueued
    }
}
