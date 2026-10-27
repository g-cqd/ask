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

    public init(
        mouse: Bool? = nil, copyOnSelect: Bool? = nil, foldTools: Bool? = nil, foldThinking: Bool? = nil,
        scrollLines: Int? = nil, promptRows: Int? = nil, foldCode: Bool? = nil, codeFoldLines: Int? = nil,
        sidebarOpen: Bool? = nil, prompt: String? = nil, tint: Bool? = nil, separator: Bool? = nil,
        padding: Bool? = nil, localizedDurations: Bool? = nil, spinner: SpinnerPreference? = nil
    ) {
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
    }

    public var isEmpty: Bool {
        mouse == nil && copyOnSelect == nil && foldTools == nil && foldThinking == nil && scrollLines == nil
            && promptRows == nil && foldCode == nil && codeFoldLines == nil && sidebarOpen == nil && prompt == nil
            && tint == nil && separator == nil && padding == nil && localizedDurations == nil && spinner == nil
        // @dl:accept -- the layering takes each key from the later section; the keys are the data
    }

    /// The keys, in the order they are shown.
    public static let keys =
        ["mouse", "copyOnSelect", "tools", "thinking", "scrollLines", "promptRows", "code", "codeFoldLines", "sidebar"]
        + lookKeys

    /// The keys that set the look of the screen (roadmap 0074).
    private static let lookKeys = ["prompt", "tint", "separator", "padding", "localizedDurations", "spinner"]

    /// `self` with every key `section` sets replaced.
    public func layered(with section: UISection) -> UISection {
        UISection(
            mouse: section.mouse ?? mouse, copyOnSelect: section.copyOnSelect ?? copyOnSelect,
            foldTools: section.foldTools ?? foldTools, foldThinking: section.foldThinking ?? foldThinking,
            scrollLines: section.scrollLines ?? scrollLines, promptRows: section.promptRows ?? promptRows,
            foldCode: section.foldCode ?? foldCode, codeFoldLines: section.codeFoldLines ?? codeFoldLines,
            sidebarOpen: section.sidebarOpen ?? sidebarOpen, prompt: section.prompt ?? prompt,
            tint: section.tint ?? tint, separator: section.separator ?? separator,
            padding: section.padding ?? padding, localizedDurations: section.localizedDurations ?? localizedDurations,
            spinner: section.spinner ?? spinner)
    }

    public var description: String {
        var parts: [String] = []
        // @dl:accept -- one line per key, as data, in the order the keys are shown
        if let mouse { parts.append("mouse \(mouse ? "on" : "off")") }
        if let copyOnSelect { parts.append("copyOnSelect \(copyOnSelect ? "on" : "off")") }
        // @dl:accept -- one line per key, as data, in the order the keys are shown
        if let foldTools { parts.append("tools \(foldTools ? "folded" : "open")") }
        if let foldThinking { parts.append("thinking \(foldThinking ? "folded" : "open")") }
        if let scrollLines { parts.append("scrollLines \(scrollLines)") }
        if let promptRows { parts.append("promptRows \(promptRows)") }
        if let foldCode { parts.append("code \(foldCode ? "folded" : "open")") }
        if let codeFoldLines { parts.append("codeFoldLines \(codeFoldLines)") }
        if let sidebarOpen { parts.append("sidebar \(sidebarOpen ? "open" : "closed")") }
        if let prompt { parts.append(prompt.isEmpty ? "prompt none" : "prompt \"\(prompt)\"") }
        if let tint { parts.append("tint \(tint ? "on" : "off")") }
        if let separator { parts.append("separator \(separator ? "on" : "off")") }
        if let padding { parts.append("padding \(padding ? "on" : "off")") }
        if let localizedDurations { parts.append("localizedDurations \(localizedDurations ? "on" : "off")") }
        if let spinner { parts.append("spinner \(spinner.rawValue)") }
        return parts.isEmpty ? "defaults" : parts.joined(separator: ", ")
    }
}
