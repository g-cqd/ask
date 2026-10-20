/// The `ui` section of a configuration file: how the screen treats the pointer and tool output (ADR-0046). Every key is optional, and a
/// layer that sets one replaces it and leaves the others.
public struct UISection: Sendable, Equatable, CustomStringConvertible {
    /// `ui.mouse`: whether the terminal reports the mouse to ask. Off leaves the terminal's own selection and wheel alone.
    public var mouse: Bool?
    /// `ui.copyOnSelect`: whether a finished selection is copied at once.
    public var copyOnSelect: Bool?
    /// `ui.tools`: whether a tool's output starts folded to one line. `true` is `"folded"`, `false` is `"open"`.
    public var foldTools: Bool?
    /// `ui.scrollLines`: how many lines one wheel step scrolls.
    public var scrollLines: Int?

    public init(mouse: Bool? = nil, copyOnSelect: Bool? = nil, foldTools: Bool? = nil, scrollLines: Int? = nil) {
        self.mouse = mouse
        self.copyOnSelect = copyOnSelect
        self.foldTools = foldTools
        self.scrollLines = scrollLines
    }

    public var isEmpty: Bool { mouse == nil && copyOnSelect == nil && foldTools == nil && scrollLines == nil }

    /// The keys, in the order they are shown.
    public static let keys = ["mouse", "copyOnSelect", "tools", "scrollLines"]

    /// `self` with every key `section` sets replaced.
    public func layered(with section: UISection) -> UISection {
        UISection(
            mouse: section.mouse ?? mouse, copyOnSelect: section.copyOnSelect ?? copyOnSelect,
            foldTools: section.foldTools ?? foldTools, scrollLines: section.scrollLines ?? scrollLines)
    }

    public var description: String {
        var parts: [String] = []
        if let mouse { parts.append("mouse \(mouse ? "on" : "off")") }
        if let copyOnSelect { parts.append("copyOnSelect \(copyOnSelect ? "on" : "off")") }
        if let foldTools { parts.append("tools \(foldTools ? "folded" : "open")") }
        if let scrollLines { parts.append("scrollLines \(scrollLines)") }
        return parts.isEmpty ? "defaults" : parts.joined(separator: ", ")
    }
}
