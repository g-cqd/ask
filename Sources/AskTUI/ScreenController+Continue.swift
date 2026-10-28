internal import Foundation
internal import TerminalKitCodecs
internal import TerminalKitInput

/// Telling the model to carry on (roadmaps 0097 and 0112): `/continue`, the bare words, and Right pressed twice.
extension ScreenController {
    /// What the model is sent, whichever way it was asked for.
    static let continueText = "Continue the work where you stopped."

    /// The words that mean it when they are the whole input; a sentence that starts with one is still a prompt.
    static func isContinueWord(_ text: String) -> Bool {
        ["continue", "resume", "go ahead", "go"]
            .contains(text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }

    /// The message for `/continue` with what was typed after it.
    static func continueText(with arguments: String) -> String {
        let extra = arguments.trimmingCharacters(in: .whitespacesAndNewlines)
        return extra.isEmpty ? continueText : continueText + " " + extra
    }

    /// How long a second Right may follow the first.
    static let continueTapWindow: Duration = .milliseconds(600)

    /// Right on an empty input while nothing runs: the first press waits for a second, which sends "continue". A held key (auto-repeat), a
    /// slow second press and any other key in between do not. Nil when the key is not that, so it moves the cursor as usual.
    mutating func continueTap(_ key: KeyEvent, at now: ContinuousClock.Instant, previous: ContinuousClock.Instant?)
        -> [Effect]?
    {
        guard key.keyCode == Key.right.rawValue, key.modifiers.isEmpty, key.eventType == .press,
            state.editor.text.isEmpty, !state.running
        else { return nil }
        if let previous, previous.duration(to: now) <= Self.continueTapWindow {
            return submit(Self.continueText, followUp: false)
        }
        state.rightTappedAt = now
        return []
    }
}
