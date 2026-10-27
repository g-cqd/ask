internal import TerminalKitCodecs
internal import TerminalKitInput

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
        if state.running {
            if options.abortTurnRequiresConfirmation {
                if let armed = state.abortArmedAt, press.at - armed <= Self.quitWindow {
                    state.abortArmedAt = nil
                    state.abortArmedAction = nil
                    return abort()
                }
                state.abortArmedAt = press.at
                state.abortArmedAction = "Ctrl+C"
                quitGeneration += 1
                return [.armQuitTimer(generation: quitGeneration)]
            }
            return abort()
        }
        if let armed = press.armedAt, press.at - armed <= Self.quitWindow { return [.quit] }
        state.quitArmedAt = press.at
        quitGeneration += 1
        return [.armQuitTimer(generation: quitGeneration)]
    }

    /// Only consecutive interrupt presses can confirm aborting the current turn.
    mutating func disarmTurnAbort(unlessInterrupt event: InputEvent) {
        switch event {
            case .key(let key):
                if key.keyCode == 0x03
                    || (key.modifiers.contains(.ctrl) && (key.keyCode == 0x63 || key.keyCode == 0x43))
                {
                    return
                }
            case .paste: break
            default: return
        }
        state.abortArmedAt = nil
        state.abortArmedAction = nil
    }

    /// The quit window ended without a second press: the hint goes. A window that was already replaced or ended is left alone.
    mutating func quitWindowEnded(generation: Int) {
        if generation == quitGeneration {
            state.quitArmedAt = nil
            state.abortArmedAt = nil
            state.abortArmedAction = nil
        }
    }
}
