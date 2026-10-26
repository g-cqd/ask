/// Details (ADR-0119): what ask did on its own account, shown only when asked for. Held back, not thrown away, so `/verbose` can show what
/// came before it.
extension ScreenController {
    /// The most details kept while they are hidden.
    static let heldDetailLimit = 50

    mutating func receive(detail text: String) {
        if state.verbose {
            state.transcript.addNotice(text, isError: false)
        } else {
            state.heldDetails.append(text)
            if state.heldDetails.count > Self.heldDetailLimit { state.heldDetails.removeFirst() }
        }
    }

    /// `/verbose`: turns details on, showing those held back, or off.
    mutating func toggleVerbose() -> [Effect] {
        state.verbose.toggle()
        guard state.verbose else {
            state.transcript.addNotice("Details are hidden. /verbose shows them again.", isError: false)
            return []
        }
        state.transcript.addNotice("Details are shown.", isError: false)
        for text in state.heldDetails { state.transcript.addNotice(text, isError: false) }
        state.heldDetails.removeAll()
        return []
    }
}
