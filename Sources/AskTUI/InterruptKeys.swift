/// Which keys interrupt a running turn (`ui.interruptKeys`).
public enum InterruptKeys: String, Sendable {
    case esc
    case ctrlC = "ctrl-c"
    case both

    /// Whether Esc may interrupt.
    var allowsEscape: Bool { self != .ctrlC }
    /// Whether Ctrl+C may interrupt.
    var allowsControlC: Bool { self != .esc }
}
