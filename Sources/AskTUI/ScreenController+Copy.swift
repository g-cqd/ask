/// A copy that reaches the host pasteboard ends later than it starts: the notice says *pending* until the command has exited.
extension ScreenController {
    /// Numbers a new copy, so a result that arrives after a newer copy began is recognised as stale and dropped.
    mutating func beginCopy() -> Int {
        copyGeneration += 1
        return copyGeneration
    }

    /// Replaces the *pending* notice with how the host pasteboard command ended, if that copy is still the latest. A notice the user
    /// cleared stays cleared, except a failure: a copy that did not work must not vanish with the highlight.
    mutating func finishCopy(_ notice: String, failed: Bool, generation: Int) {
        guard generation == copyGeneration, failed || !state.clipboardNotice.isEmpty else { return }
        state.clipboardNotice = notice
    }
}
