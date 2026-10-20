internal import TerminalKitCodecs

/// The approval question (roadmap 0019): shown with how to answer it, and answered by one key.
extension ScreenController {
    mutating func ask(id: Int, question: String) {
        state.pendingApproval = PendingApproval(id: id, question: question)
        state.scrollback = 0
        state.transcript.addNotice(question + "  y once · a for this session · n no", isError: false)
    }

    /// y, a or n answer the question, and Esc is no rather than an abort; Ctrl-C still aborts the turn. Other keys
    /// are ignored, so a stray key neither answers nor types into the prompt.
    mutating func answer(_ key: KeyEvent) -> [Effect] {
        guard let pending = state.pendingApproval else { return [] }
        // Ctrl-C keeps its meaning: abort the turn. Cancelling it answers the question no.
        if key.keyCode == 0x03 || (key.modifiers.contains(.ctrl) && (key.keyCode == 0x63 || key.keyCode == 0x43)) {
            state.pendingApproval = nil
            return abort()
        }
        let choice: ApprovalChoice
        switch key.keyCode {
            case 0x79, 0x59: choice = .once  // y
            case 0x61, 0x41: choice = .session  // a
            case 0x6E, 0x4E, 0x1B: choice = .deny  // n, Esc
            default: return []
        }
        state.pendingApproval = nil
        let said =
            switch choice {
                case .once: "Allowed once."
                case .session: "Allowed for this session."
                case .deny: "Not allowed."
            }
        state.transcript.addNotice(said, isError: false)
        return [.answerApproval(id: pending.id, choice)]
    }
}
