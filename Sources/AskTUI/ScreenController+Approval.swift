internal import TerminalKitCodecs
internal import TerminalKitInput

/// The approval question (roadmaps 0019 and 0116): a section of checkboxes above the input. The arrows move, Space checks, a number or a
/// letter checks its row, Enter confirms; Esc denies at once; Ctrl+C stops the turn. Once answered, the question stays in the
/// conversation as one block with its answer.
extension ScreenController {
    mutating func ask(id: Int, question: String, kind: ApprovalKind = .grant) {
        state.pendingApproval = PendingApproval(id: id, question: question, kind: kind)
        state.scrollback = 0
    }

    /// Other keys are ignored, so a stray key neither answers nor types into the prompt.
    mutating func answer(_ key: KeyEvent) -> [Effect] {
        guard var pending = state.pendingApproval else { return [] }
        // Ctrl-C keeps its meaning: abort the turn. Cancelling it answers the question no.
        if key.keyCode == 0x03 || (key.modifiers.contains(.ctrl) && (key.keyCode == 0x63 || key.keyCode == 0x43)) {
            settle(pending, saying: "denied")
            return abort()
        }
        let options = pending.options
        switch key.keyCode {
            case 0x1B:
                let deny = options.last!
                settle(pending, saying: deny.said)
                return [.answerApproval(id: pending.id, deny.choice)]
            case 0x0D:
                let chosen = options[pending.checked]
                settle(pending, saying: chosen.said)
                return [.answerApproval(id: pending.id, chosen.choice)]
            case Key.up.rawValue: pending.cursor = Swift.max(0, pending.cursor - 1)
            case Key.down.rawValue: pending.cursor = Swift.min(options.count - 1, pending.cursor + 1)
            case 0x20: pending.checked = pending.cursor
            default:
                guard let row = Self.shortcut(key, in: options) else { return [] }
                pending.cursor = row
                pending.checked = row
        }
        state.pendingApproval = pending
        return []
    }

    /// The row a number (from 1) or a letter names, if any.
    private static func shortcut(_ key: KeyEvent, in options: [ApprovalOption]) -> Int? {
        guard key.modifiers.isEmpty, let scalar = Unicode.Scalar(key.keyCode) else { return nil }
        let character = Character(scalar)
        if let number = character.wholeNumberValue, (1 ... options.count).contains(number) { return number - 1 }
        return options.firstIndex { $0.letter == Character(character.lowercased()) }
    }

    /// Ends the question, leaving it in the conversation as one block with its answer.
    private mutating func settle(_ pending: PendingApproval, saying said: String) {
        state.pendingApproval = nil
        state.transcript.addNotice(pending.question + " → " + said, isError: false)
    }
}
