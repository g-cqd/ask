internal import AskCore

/// Which keys interrupt a running turn (`ui.interruptKeys`).
extension InterruptKeys {
    /// Whether Esc may interrupt.
    var allowsEscape: Bool { self != .ctrlC }
    /// Whether Ctrl+C may interrupt.
    var allowsControlC: Bool { self != .esc }
}
