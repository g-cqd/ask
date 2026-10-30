internal import AskAgentCore
internal import AskTUI
internal import Foundation
internal import Synchronization

extension AgentConversation {
    /// The most turns `/tree` lists; the numbers it shows work for every turn, listed or not.
    private static let treeListingLimit = 40

    /// `/tree` lists the session's prompts; `/tree N` goes back to before prompt N (ADR-0093).
    ///
    /// Going back moves the session's leaf to the entry that prompt followed and puts its text in the editor. Nothing is removed: the
    /// turns that came after stay in the session as another branch, and the next message sent continues from where the person went back
    /// to. The same session stays open, so jobs, the model and the sandbox are untouched.
    func tree(arguments: String, update: @Sendable (ConversationUpdate) -> Void) {
        guard let recorder = session.withLock({ $0 }), !SessionOutline(recorder.tree).turns.isEmpty else {
            update(.notice("Nothing to go back to yet: no prompt has been sent in this session.", isError: false))
            return
        }
        let outline = SessionOutline(recorder.tree)
        let wanted = arguments.trimmingCharacters(in: .whitespaces)
        guard !wanted.isEmpty else {
            list(outline, update: update)
            return
        }
        guard let number = Int(wanted), let turn = outline.turn(number) else {
            update(
                .notice(
                    "Usage: /rewind to list the prompts, /rewind N to go back to before prompt N (1 to \(outline.turns.count)).",
                    isError: true))
            return
        }
        do {
            try recorder.moveLeaf(to: turn.before)
        } catch {
            update(.notice("Cannot go back to prompt \(number): \(error)", isError: true))
            return
        }
        usage.withLock { $0 = UsageTotals() }
        // One update, drawn once: item by item, a long session took seconds to draw again (roadmap 0160).
        update(.batch([.clearConversation] + history() + [.fillDraft(turn.text)]))
        update(
            .notice(
                "Went back to before prompt \(number). What you send next continues from here; the later turns are kept as another branch (/tree).",
                isError: false))
    }

    /// The prompts as the rows of the `/tree` picker; choosing one is `/tree N`. The prompts on the path the session is at are marked.
    func treeRows() -> [ChoiceRow] {
        guard let recorder = session.withLock({ $0 }) else { return [] }
        return SessionOutline(recorder.tree).picks()
            .map { pick in
                ChoiceRow(
                    label: String(pick.number),
                    detail: ([pick.text, pick.note].filter { !$0.isEmpty }).joined(separator: "  ·  "),
                    arguments: String(pick.number), isCurrent: pick.isOnActiveBranch)
            }
    }

    private func list(_ outline: SessionOutline, update: @Sendable (ConversationUpdate) -> Void) {
        let lines = outline.lines()
        var report = [
            "Prompts in this session (> is the path you are on). /rewind N goes back to before prompt N and puts it back in the editor:"
        ]
        report.append(contentsOf: lines.suffix(Self.treeListingLimit))
        if lines.count > Self.treeListingLimit {
            report.append("Showing the last \(Self.treeListingLimit) of \(lines.count); every number works.")
        }
        update(.notice(report.joined(separator: "\n"), isError: false))
    }
}
