internal import AskAgentCore
internal import AskTUI
internal import Foundation
internal import Synchronization
internal import System

extension AgentConversation {
    /// `/fork` continues this conversation in a new session; `/fork N` does the same from before prompt N, with that prompt back in the
    /// editor (ADR-0094).
    ///
    /// The new file holds the branch and the strict sandbox the session ran under, and the original is not touched: it stays saved, with
    /// every branch it had. The switch follows `/resume`'s rules (ADR-0041): only between turns, and not while jobs run, because a
    /// session does not own processes.
    func forkSession(arguments: String, update: @Sendable (ConversationUpdate) -> Void) async {
        guard
            let original = recordedSession(
                orSay: "Nothing to fork yet: no prompt has been sent in this session.",
                update: update
            )
        else { return }
        let outline = SessionOutline(original.tree)
        let wanted = arguments.trimmingCharacters(in: .whitespaces)
        var leaf = original.tree.leaf
        var returned: String?
        if !wanted.isEmpty {
            guard let number = Int(wanted), let turn = outline.turn(number) else {
                update(
                    .notice(
                        "Usage: /fork to continue in a new session, /fork N to do so from before prompt N (1 to \(outline.turns.count)).",
                        isError: true
                    )
                )
                return
            }
            (leaf, returned) = (turn.before, turn.text)
        }
        if turnRunning { return forkBeside(original, upTo: leaf, update: update) }
        guard maySwitchSession("fork", update: update) else { return }
        do {
            let replacement = try forked(original, upTo: leaf)
            activateSession(replacement, update: update)
            await adoptRecords(of: replacement, update: update)
            if let returned { update(.fillDraft(returned)) }
            let name = (replacement.path as NSString).lastPathComponent
            let was = (original.path as NSString).lastPathComponent
            update(
                .notice(
                    "Forked into session \(name). The original, \(was), is unchanged and still saved.",
                    isError: false
                )
            )
        } catch {
            update(.notice("Cannot fork: \(error)", isError: true))
        }
    }

    /// A new session holding `original` up to `leaf`, with a copy of its task list when the list is its own (ADR-0140).
    func forked(_ original: SessionRecorder, upTo leaf: EntryID?) throws -> SessionRecorder {
        try directory.create()
        let copy = try original.fork(upTo: leaf, to: FilePath(directory.newSessionPath()))
        let scope = current.withLock { $0.settings.configuration.taskScope.value }
        TaskBoard.copyForFork(from: original.path, to: copy.path, scope: scope)
        IdeaBoard.copyForFork(from: original.path, to: copy.path, scope: scope)
        return copy
    }

    /// `/fork` while a turn runs (roadmap 0113): the copy holds what the turn has written so far, every step written whole, and the
    /// screen stays with the turn, which goes on in the original; `/resume` switches to the copy.
    private func forkBeside(
        _ original: SessionRecorder,
        upTo leaf: EntryID?,
        update: @Sendable (ConversationUpdate) -> Void
    ) {
        do {
            let copy = try forked(original, upTo: leaf)
            let name = (copy.path as NSString).lastPathComponent
            update(
                .notice(
                    "Forked into session \(name), up to what the turn has written so far. The turn goes on here; /resume \(name) "
                        + "switches to the copy.",
                    isError: false
                )
            )
        } catch {
            update(.notice("Cannot fork: \(error)", isError: true))
        }
    }
}
