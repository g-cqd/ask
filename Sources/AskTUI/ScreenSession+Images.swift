internal import TerminalKitIO
internal import TerminalKitInput

/// The screen's pictures as pixels (roadmap 0208): the terminal's answer, and placing what is new once an update is applied.
extension ScreenSession {
    /// Takes the terminal's answer to the graphics query, which nothing else should see; false for any other event.
    func takeImageAnswer(_ event: ScreenEvent) -> Bool {
        guard images != nil, case .input(let input) = event, case .unknown(let bytes) = input else { return false }
        guard images?.take(bytes) == true else { return false }
        placeImages()
        return true
    }

    /// Sends and places the pictures not placed yet, sized to the terminal's cells, and draws again when one was. The width left
    /// for them is the transcript's less a padded block's inset, which only ever makes them narrower.
    func placeImages() {
        guard var held = images, let size = terminalSize() else { return }
        let placed = held.place(in: &controller.state.transcript, size: size, inset: 1)
        images = held
        if placed { render() }
    }
}
