/// How the screen treats the pointer. The defaults are ADR-0046's; the composition root fills them from `ui.*` configuration.
public struct ScreenOptions: Sendable, Equatable {
    /// Whether the terminal reports the mouse to ask. Off leaves the terminal's own selection and wheel alone.
    public var mouse: Bool
    /// Whether a finished selection is copied at once. Off keeps it highlighted and does not copy it.
    public var copyOnSelect: Bool
    /// How many lines one wheel step scrolls. Terminals send different numbers of steps for one gesture (TerminalKit ADR-0028).
    public var scrollLines: Int

    public init(mouse: Bool = true, copyOnSelect: Bool = true, scrollLines: Int = 3) {
        self.mouse = mouse
        self.copyOnSelect = copyOnSelect
        self.scrollLines = Swift.max(1, scrollLines)
    }
}
