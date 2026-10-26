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
    /// Whether the terminal's background is light, which picks the lighter tints; the composition root reads it from the environment.
    public var lightBackground: Bool

    /// The look before roadmap 0074: an `ask> ` prefix, no tint, no rule. What the screen's older tests were written against.
    public static let legacy = ScreenOptions(prompt: "ask> ", tint: false, separator: false)

    public init(
        mouse: Bool = true, copyOnSelect: Bool = true, foldTools: Bool = true, foldThinking: Bool = true,
        scrollLines: Int = 3, promptRows: Int = 6, foldCode: Bool = true, codeFoldLines: Int = 20,
        sidebar: Bool = false, verbose: Bool = false, prompt: String = "", tint: Bool = true, separator: Bool = true,
        lightBackground: Bool = false
    ) {
        self.mouse = mouse
        self.copyOnSelect = copyOnSelect
        self.foldTools = foldTools
        self.foldThinking = foldThinking
        self.scrollLines = Swift.max(1, scrollLines)
        self.promptRows = Swift.max(1, promptRows)
        self.foldCode = foldCode
        self.codeFoldLines = Swift.max(1, codeFoldLines)
        self.sidebar = sidebar
        self.verbose = verbose
        self.prompt = prompt
        self.tint = tint
        self.separator = separator
        self.lightBackground = lightBackground
    }
}
