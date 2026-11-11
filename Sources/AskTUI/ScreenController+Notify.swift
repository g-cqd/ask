/// `ui.notify` (note n62; the owner's answers of 2026-11-11): while the terminal is not focused, or has not said, a turn's end and
/// a question for the person are told with a bell or a notification (``TerminalNotification``).
extension ScreenController {
    /// The notification saying `what`, when notifications are on and the terminal is not known to be focused; else nothing.
    func notifyingAway(_ what: String) -> [Effect] {
        guard options.notify != .off, state.focused != true else { return [] }
        return [.notify("\(tabTitle): \(what)")]
    }

    /// What the terminal says of its focus (`?1004`), which it reports only while notifications are on.
    mutating func noteFocus(_ focused: Bool) -> [Effect] {
        state.focused = focused
        return []
    }
}
