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

    public init(
        mouse: Bool? = nil, copyOnSelect: Bool? = nil, foldTools: Bool? = nil, foldThinking: Bool? = nil,
        scrollLines: Int? = nil, promptRows: Int? = nil, foldCode: Bool? = nil, codeFoldLines: Int? = nil,
        sidebarOpen: Bool? = nil, prompt: String? = nil, tint: Bool? = nil, separator: Bool? = nil,
        padding: Bool? = nil, localizedDurations: Bool? = nil, spinner: SpinnerPreference? = nil,
        // @dl:accept -- optional settings are schema data: each parameter names a key
        jobAutoReturnWhenFocused: Bool? = nil, abortTurnRequiresConfirmation: Bool? = nil,
        // @dl:accept -- optional settings are schema data: each parameter names a key
        interruptKeys: InterruptKeysPreference? = nil, escapeInterruptRequiresConfirmation: Bool? = nil,
        interruptSendsQueued: QueuedAfterInterruptPreference? = nil, onlyUsefulModels: Bool? = nil,
        appearance: AppearancePreference? = nil
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
        self.localizedDurations = localizedDurations
        self.spinner = spinner
        self.jobAutoReturnWhenFocused = jobAutoReturnWhenFocused
        self.abortTurnRequiresConfirmation = abortTurnRequiresConfirmation
        self.interruptKeys = interruptKeys
        self.escapeInterruptRequiresConfirmation = escapeInterruptRequiresConfirmation
        self.interruptSendsQueued = interruptSendsQueued
        self.onlyUsefulModels = onlyUsefulModels
        self.appearance = appearance
    }

    public var isEmpty: Bool {
        mouse == nil && copyOnSelect == nil && foldTools == nil && foldThinking == nil && scrollLines == nil
            && promptRows == nil && foldCode == nil && codeFoldLines == nil && sidebarOpen == nil && prompt == nil
            && tint == nil && separator == nil && padding == nil && localizedDurations == nil && spinner == nil
            && jobAutoReturnWhenFocused == nil && abortTurnRequiresConfirmation == nil && interruptKeys == nil
            && escapeInterruptRequiresConfirmation == nil && interruptSendsQueued == nil
            && onlyUsefulModels == nil && appearance == nil
        // @dl:accept -- the layering takes each key from the later section; the keys are the data
    }

    /// The keys, in the order they are shown.
    public static let keys =
        ["mouse", "copyOnSelect", "tools", "thinking", "scrollLines", "promptRows", "code", "codeFoldLines", "sidebar"]
        + lookKeys + behaviorKeys

    /// The keys that set the look of the screen (roadmap 0074).
    private static let lookKeys = [
        // @dl:accept -- the key table is schema data
        "prompt", "tint", "appearance", "separator", "padding", "localizedDurations", "spinner"
    ]
    private static let behaviorKeys = [
        "jobAutoReturnWhenFocused", "abortTurnRequiresConfirmation", "interruptKeys",
        "escapeInterruptRequiresConfirmation", "interruptSendsQueued", "onlyUsefulModels"
    ]

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
            padding: section.padding ?? padding, localizedDurations: section.localizedDurations ?? localizedDurations,
            spinner: section.spinner ?? spinner,
            jobAutoReturnWhenFocused: section.jobAutoReturnWhenFocused ?? jobAutoReturnWhenFocused,
            abortTurnRequiresConfirmation: section.abortTurnRequiresConfirmation ?? abortTurnRequiresConfirmation,
            interruptKeys: section.interruptKeys ?? interruptKeys,
            escapeInterruptRequiresConfirmation: section.escapeInterruptRequiresConfirmation
                ?? escapeInterruptRequiresConfirmation,
            interruptSendsQueued: section.interruptSendsQueued ?? interruptSendsQueued,
            onlyUsefulModels: section.onlyUsefulModels ?? onlyUsefulModels,
            appearance: section.appearance ?? appearance)
    }

    public var description: String {
        var parts: [String] = []
        func flag(_ name: String, _ value: Bool?) {
            if let value { parts.append("\(name) \(value ? "on" : "off")") }
        }
        // @dl:accept -- one line per key, as data, in the order the keys are shown
        flag("mouse", mouse)
        flag("copyOnSelect", copyOnSelect)
        // @dl:accept -- one line per key, as data, in the order the keys are shown
        if let foldTools { parts.append("tools \(foldTools ? "folded" : "open")") }
        // @dl:accept -- one line per key, as data, in the order the keys are shown
        if let foldThinking { parts.append("thinking \(foldThinking ? "folded" : "open")") }
        if let scrollLines { parts.append("scrollLines \(scrollLines)") }
        if let promptRows { parts.append("promptRows \(promptRows)") }
        if let foldCode { parts.append("code \(foldCode ? "folded" : "open")") }
        if let codeFoldLines { parts.append("codeFoldLines \(codeFoldLines)") }
        if let sidebarOpen { parts.append("sidebar \(sidebarOpen ? "open" : "closed")") }
        // @dl:accept -- named UI fields form the user-facing configuration listing
        if let prompt { parts.append(prompt.isEmpty ? "prompt none" : "prompt \"\(prompt)\"") }
        flag("tint", tint)
        if let appearance { parts.append("appearance \(appearance.rawValue)") }
        flag("separator", separator)
        flag("padding", padding)
        flag("localizedDurations", localizedDurations)
        if let spinner { parts.append("spinner \(spinner.rawValue)") }
        flag("jobAutoReturnWhenFocused", jobAutoReturnWhenFocused)
        flag("abortTurnRequiresConfirmation", abortTurnRequiresConfirmation)
        if let interruptKeys { parts.append("interruptKeys \(interruptKeys.rawValue)") }
        flag("escapeInterruptRequiresConfirmation", escapeInterruptRequiresConfirmation)
        if let interruptSendsQueued { parts.append("interruptSendsQueued \(interruptSendsQueued.rawValue)") }
        flag("onlyUsefulModels", onlyUsefulModels)
        return parts.isEmpty ? "defaults" : parts.joined(separator: ", ")
    }
}
