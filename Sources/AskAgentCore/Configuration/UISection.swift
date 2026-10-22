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

    public init(
        mouse: Bool? = nil, copyOnSelect: Bool? = nil, foldTools: Bool? = nil, foldThinking: Bool? = nil,
        scrollLines: Int? = nil, promptRows: Int? = nil
    ) {
        self.mouse = mouse
        self.copyOnSelect = copyOnSelect
        self.foldTools = foldTools
        self.foldThinking = foldThinking
        self.scrollLines = scrollLines
        self.promptRows = promptRows
    }

    public var isEmpty: Bool {
        mouse == nil && copyOnSelect == nil && foldTools == nil && foldThinking == nil && scrollLines == nil
            && promptRows == nil
    }

    /// The keys, in the order they are shown.
    public static let keys = ["mouse", "copyOnSelect", "tools", "thinking", "scrollLines", "promptRows"]

    /// `self` with every key `section` sets replaced.
    public func layered(with section: UISection) -> UISection {
        UISection(
            mouse: section.mouse ?? mouse, copyOnSelect: section.copyOnSelect ?? copyOnSelect,
            foldTools: section.foldTools ?? foldTools, foldThinking: section.foldThinking ?? foldThinking,
            scrollLines: section.scrollLines ?? scrollLines, promptRows: section.promptRows ?? promptRows)
    }

    public var description: String {
        var parts: [String] = []
        if let mouse { parts.append("mouse \(mouse ? "on" : "off")") }
        if let copyOnSelect { parts.append("copyOnSelect \(copyOnSelect ? "on" : "off")") }
        if let foldTools { parts.append("tools \(foldTools ? "folded" : "open")") }
        if let foldThinking { parts.append("thinking \(foldThinking ? "folded" : "open")") }
        if let scrollLines { parts.append("scrollLines \(scrollLines)") }
        if let promptRows { parts.append("promptRows \(promptRows)") }
        return parts.isEmpty ? "defaults" : parts.joined(separator: ", ")
    }
}
