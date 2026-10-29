/// A click on the idle status mark names the sandbox state for a few seconds (roadmap 0133).
extension ScreenController {
    /// How long the word stays before the mark comes back.
    static let sandboxNoteWindow: Duration = .seconds(5)

    /// Shows the word, or takes it away at once when it is up. Either way an earlier timer stops meaning anything.
    mutating func toggleSandboxNote() -> [Effect] {
        state.sandboxNoteGeneration += 1
        state.sandboxNoteShown.toggle()
        return state.sandboxNoteShown ? [.armSandboxNoteTimer(generation: state.sandboxNoteGeneration)] : []
    }

    /// The note's time is up; a timer from a note that was closed or replaced is ignored.
    mutating func sandboxNoteEnded(generation: Int) {
        if generation == state.sandboxNoteGeneration { state.sandboxNoteShown = false }
    }
}
