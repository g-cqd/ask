internal import TerminalKitInput
internal import TerminalKitText

/// The wheel over a draft too tall for its window scrolls the window, one display row a step, and leaves the cursor where it is.
extension ScreenController {
    /// Returns whether the input took the step. A draft that fits has nothing to scroll, so the step goes on to the transcript; one that
    /// does not fit keeps every step, even at its ends, rather than passing the rest of a gesture to the transcript under it.
    mutating func scrollInput(_ direction: WheelDirection) -> Bool {
        guard let layout = frame.prompt, layout.rows.count > frame.promptRows, direction == .up || direction == .down
        else {
            return false
        }
        let top = state.promptScroll ?? frame.promptTop
        let last = layout.rows.count - frame.promptRows
        state.promptScroll = Swift.min(Swift.max(top + (direction == .up ? -1 : 1), 0), last)
        return true
    }
}
