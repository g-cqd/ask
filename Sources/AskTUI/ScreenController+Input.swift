internal import TerminalKitCodecs
internal import TerminalKitInput

/// A line a running command asks for, such as a code pasted from a browser or an API key (ADR-0117).
///
/// The keys go to a buffer of their own, not the draft, so a secret is not in the editor, the transcript, the scrollback or a session
/// file. The status line shows the question and what was typed, as dots for a secret; Enter sends it, Esc cancels it.
extension ScreenController {
    mutating func askInput(id: Int, prompt: String, secret: Bool) {
        state.pendingInput = PendingInput(id: id, prompt: prompt, secret: secret)
        state.inputAnswer.clear()
        state.scrollback = 0
        state.transcript.addNotice(prompt, isError: false)
    }

    /// Enter sends what was typed, Esc cancels, Ctrl+C cancels and stops the command; every other key edits the answer.
    mutating func answerInput(_ key: KeyEvent) -> [Effect] {
        guard let pending = state.pendingInput else { return [] }
        let finish = { (state: inout ScreenState) in
            state.pendingInput = nil
            state.inputAnswer.clear()
        }
        if key.keyCode == 0x03 || (key.modifiers.contains(.ctrl) && (key.keyCode == 0x63 || key.keyCode == 0x43)) {
            finish(&state)
            return [.answerInput(id: pending.id, text: nil)] + abort()
        }
        switch key.keyCode {
            case 0x1B:
                finish(&state)
                state.transcript.addNotice("Cancelled.", isError: false)
                return [.answerInput(id: pending.id, text: nil)]
            case 0x0D where !key.modifiers.contains(.shift):
                let text = state.inputAnswer.text
                finish(&state)
                state.transcript.addNotice(pending.secret ? "Received (hidden)." : "Received.", isError: false)
                return [.answerInput(id: pending.id, text: text)]
            default:
                _ = state.inputAnswer.apply(key)
                return []
        }
    }
}
