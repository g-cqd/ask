/// Ctrl+C, one step a press (roadmap 0064, ADR-0103): erase what is typed, then stop what is running, then arm the quit, and quit on a second press within
/// the window. A first press never quits, and nothing but Ctrl+C itself ever stops a turn.
extension ScreenController {
    /// How long after the arming press a second Ctrl+C still quits.
    static let quitWindow = Duration.seconds(2)

    /// When a Ctrl+C arrived, and when the quit was armed, if it was.
    struct Interrupt {
        let at: ContinuousClock.Instant
        let armedAt: ContinuousClock.Instant?
    }

    /// The step this press takes. A selection took Ctrl+C before this point, and a pending question has its own.
    mutating func interrupted(_ press: Interrupt) -> [Effect] {
        if !state.editor.text.isEmpty {
            state.editor.clear()
            return []
        }
        if state.running { return abort() }
        if let armed = press.armedAt, press.at - armed <= Self.quitWindow { return [.quit] }
        state.quitArmedAt = press.at
        quitGeneration += 1
        return [.armQuitTimer(generation: quitGeneration)]
    }

    /// The quit window ended without a second press: the hint goes. A window that was already replaced or ended is left alone.
    mutating func quitWindowEnded(generation: Int) {
        if generation == quitGeneration { state.quitArmedAt = nil }
    }
}
