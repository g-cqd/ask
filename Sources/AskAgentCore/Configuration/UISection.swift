/// The `ui` section of a configuration file: how the screen treats the pointer and tool output (ADR-0046). Every key is optional, and a
/// layer that sets one replaces it and leaves the others.
public struct UISection: Sendable, Equatable, CustomStringConvertible {
    /// `ui.mouse`: whether the terminal reports the mouse to ask. Off leaves the terminal's own selection and wheel alone.
    public var mouse: Bool?
    /// `ui.copyOnSelect`: whether a finished selection is copied at once.
    public var copyOnSelect: Bool?
    /// `ui.tools`: whether a tool's output starts folded to one line. `true` is `"folded"`, `false` is `"open"`.
    public var foldTools: Bool?
    /// `ui.thinking`: whether the model's reasoning starts folded to one line. `true` is `"folded"`, `false` is `"open"`.
    public var foldThinking: Bool?
    /// `ui.scrollLines`: how many lines one wheel step scrolls.
    public var scrollLines: Int?
    /// `ui.promptRows`: the requested maximum display rows of the scrolling prompt.
    public var promptRows: Int?
    /// `ui.code`: whether a long code block starts folded to one line. `true` is `"folded"`, `false` is `"open"`.
    public var foldCode: Bool?
    /// `ui.codeFoldLines`: a code block with more lines than this starts folded (never more than half the screen).
    public var codeFoldLines: Int?
    /// `ui.sidebar`: whether the runner sidebar starts open. `true` is `"open"`, `false` is `"closed"`.
    public var sidebarOpen: Bool?
    /// `ui.prompt`: what the input starts with, if anything. Empty is none, which is the default: the input is marked by its tint.
    public var prompt: String?
    /// `ui.tint`: whether the input and the tool and user blocks have a tinted background. `true` is `"on"`, `false` is `"off"`.
    // @dl:accept -- optional UI settings are schema data, not the unrelated MCP annotation fields
    public var tint: Bool?
    /// `ui.separator`: whether a rule separates the conversation from the input. `true` is `"on"`, `false` is `"off"`.
    public var separator: Bool?
    /// `ui.padding`: whether each block has a row of padding around it. `true` is `"on"`, `false` is `"off"`.
    public var padding: Bool?
    /// `ui.markdown`: whether the assistant's messages are drawn as Markdown (`"on"`, default) or as the text the model wrote (`"off"`).
    public var markdown: Bool?
    /// `ui.localizedDurations`: localized elapsed units (`"on"`, default) or a compact clock (`"off"`).
    public var localizedDurations: Bool?
    /// `ui.spinner`: the spinner style used for progress and status line indicators.
    public var spinner: SpinnerPreference?
    /// `ui.appearance`: the tints follow the terminal's colours (`"auto"`, default) or are fixed for a `"light"` or `"dark"` page.
    public var appearance: AppearancePreference?
    /// `ui.jobAutoReturnWhenFocused`: whether leaving a focused job lane automatically returns to main when the job ends.
    public var jobAutoReturnWhenFocused: Bool?
    /// `ui.abortTurnRequiresConfirmation`: whether aborting an active conversation turn requires two Ctrl+C presses within two seconds.
    public var abortTurnRequiresConfirmation: Bool?
    /// `ui.interruptKeys`: which keys interrupt a running turn: `"esc"`, `"ctrl-c"` or `"both"` (default).
    public var interruptKeys: InterruptKeysPreference?
    /// `ui.escapeInterruptRequiresConfirmation`: whether Esc must be pressed twice to interrupt (`"on"`, default) or once (`"off"`).
    public var escapeInterruptRequiresConfirmation: Bool?
    /// `ui.interruptSendsQueued`: what happens to queued messages after an interruption: `"none"`, `"next"` or `"all"` (default).
    public var interruptSendsQueued: QueuedAfterInterruptPreference?
    /// `ui.onlyUsefulModels`: whether model lists leave out the models of no use to ask (`"on"`, default; roadmap 0089).
    public var onlyUsefulModels: Bool?
    /// `ui.timeout`: when a command's timeout is written: `"auto"` (default), `"always"` or `"never"` (roadmap 0126).
    public var timeout: TimeoutPreference?
    /// `ui.timeoutLabel`: the word in front of a command's timeout, 1 to 8 characters (`"timeout"` by default).
    public var timeoutLabel: String?

    public init(
        mouse: Bool? = nil, copyOnSelect: Bool? = nil, foldTools: Bool? = nil, foldThinking: Bool? = nil,
        scrollLines: Int? = nil, promptRows: Int? = nil, foldCode: Bool? = nil, codeFoldLines: Int? = nil,
        sidebarOpen: Bool? = nil, prompt: String? = nil, tint: Bool? = nil, separator: Bool? = nil,
        padding: Bool? = nil, markdown: Bool? = nil, localizedDurations: Bool? = nil, spinner: SpinnerPreference? = nil,
        // @dl:accept -- optional settings are schema data: each parameter names a key
        jobAutoReturnWhenFocused: Bool? = nil, abortTurnRequiresConfirmation: Bool? = nil,
        // @dl:accept -- optional settings are schema data: each parameter names a key
        interruptKeys: InterruptKeysPreference? = nil, escapeInterruptRequiresConfirmation: Bool? = nil,
        interruptSendsQueued: QueuedAfterInterruptPreference? = nil, onlyUsefulModels: Bool? = nil,
        appearance: AppearancePreference? = nil, timeout: TimeoutPreference? = nil, timeoutLabel: String? = nil
    ) {
        // @dl:accept -- optional configuration and resolved screen options deliberately assign the same UI keys
        self.mouse = mouse
        self.copyOnSelect = copyOnSelect
        self.foldTools = foldTools
        self.foldThinking = foldThinking
        self.scrollLines = scrollLines
        self.promptRows = promptRows
        self.foldCode = foldCode
        self.codeFoldLines = codeFoldLines
        self.sidebarOpen = sidebarOpen
        self.prompt = prompt
        self.tint = tint
        self.separator = separator
        self.padding = padding
        self.markdown = markdown
        self.localizedDurations = localizedDurations
        self.spinner = spinner
        self.jobAutoReturnWhenFocused = jobAutoReturnWhenFocused
        // @dl:accept -- one assignment per key: the initializer is the schema, as any memberwise initializer
        self.abortTurnRequiresConfirmation = abortTurnRequiresConfirmation
        self.interruptKeys = interruptKeys
        self.escapeInterruptRequiresConfirmation = escapeInterruptRequiresConfirmation
        self.interruptSendsQueued = interruptSendsQueued
        self.onlyUsefulModels = onlyUsefulModels
        self.appearance = appearance
        self.timeout = timeout
        self.timeoutLabel = timeoutLabel
    }

    public var isEmpty: Bool {
        mouse == nil && copyOnSelect == nil && foldTools == nil && foldThinking == nil && scrollLines == nil
            && promptRows == nil && foldCode == nil && codeFoldLines == nil && sidebarOpen == nil && prompt == nil
            && tint == nil && separator == nil && padding == nil && markdown == nil && localizedDurations == nil
            && spinner == nil
            && jobAutoReturnWhenFocused == nil && abortTurnRequiresConfirmation == nil && interruptKeys == nil
            && escapeInterruptRequiresConfirmation == nil && interruptSendsQueued == nil
            && onlyUsefulModels == nil && appearance == nil && timeout == nil && timeoutLabel == nil
        // @dl:accept -- the layering takes each key from the later section; the keys are the data
    }

    /// The keys, in the order they are shown, as a file writes them (roadmap 0154); `fold.*` are the keys of the `fold` object.
    public static let keys =
        [
            "mouse", "copyOnSelect", "fold.tools", "fold.thinking", "fold.code", "fold.codeLines", "scrollLines",
            "inputRows", "sidebar"
        ]
        + lookKeys + behaviorKeys

    /// The keys that set the look of the screen (roadmap 0074).
    // @dl:accept -- the key table is schema data, a list of names like a test's list of names
    private static let lookKeys = [
        // @dl:accept -- a list of key names is data, like any other list of names
        "inputPrefix", "tint", "appearance", "separator", "padding", "markdown", "durations", "spinner", "showTimeout",
        "timeoutLabel"
    ]
    private static let behaviorKeys = ["leaveFinishedJob", "stopKeys", "stopTwice", "queuedOnStop", "listAllModels"]

    /// `self` with every key `section` sets replaced.
    public func layered(with section: UISection) -> UISection {
        UISection(
            // @dl:accept -- each configuration field independently takes its later non-nil value
            mouse: section.mouse ?? mouse, copyOnSelect: section.copyOnSelect ?? copyOnSelect,
            foldTools: section.foldTools ?? foldTools, foldThinking: section.foldThinking ?? foldThinking,
            scrollLines: section.scrollLines ?? scrollLines, promptRows: section.promptRows ?? promptRows,
            foldCode: section.foldCode ?? foldCode, codeFoldLines: section.codeFoldLines ?? codeFoldLines,
            sidebarOpen: section.sidebarOpen ?? sidebarOpen, prompt: section.prompt ?? prompt,
            tint: section.tint ?? tint, separator: section.separator ?? separator,
            padding: section.padding ?? padding, markdown: section.markdown ?? markdown,
            localizedDurations: section.localizedDurations ?? localizedDurations,
            spinner: section.spinner ?? spinner,
            jobAutoReturnWhenFocused: section.jobAutoReturnWhenFocused ?? jobAutoReturnWhenFocused,
            abortTurnRequiresConfirmation: section.abortTurnRequiresConfirmation ?? abortTurnRequiresConfirmation,
            interruptKeys: section.interruptKeys ?? interruptKeys,
            escapeInterruptRequiresConfirmation: section.escapeInterruptRequiresConfirmation
                ?? escapeInterruptRequiresConfirmation,
            interruptSendsQueued: section.interruptSendsQueued ?? interruptSendsQueued,
            onlyUsefulModels: section.onlyUsefulModels ?? onlyUsefulModels,
            appearance: section.appearance ?? appearance, timeout: section.timeout ?? timeout,
            timeoutLabel: section.timeoutLabel ?? timeoutLabel)
    }

    /// The keys this section sets, as a file writes them: `inputRows 4, fold.tools false`.
    public var description: String {
        SectionText.describe(Self.keys, value(forKey:))
    }
}
