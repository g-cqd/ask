internal import AskAI
internal import AskAgentCore
internal import AskTUI
internal import Synchronization

/// A thread merges into its parent (roadmap 0195, the owner's answers of 2026-11-04): once its run has ended and every thread under it
/// has merged, one more request, like a compaction, writes the summary its parent receives in place of what it did. A thread that
/// failed or was stopped asks first. Merges go from the bottom up: a parent held by its threads is settled again when the last merges.
extension AgentConversation {
    /// Merges thread `name` if it is ready, holds it if a thread under it has not merged, or asks first if its run did not finish.
    /// Nothing while ask quits: what it stopped stays unmerged.
    func settle(_ name: String, update: @escaping @Sendable (ConversationUpdate) -> Void) async {
        guard !threads.isQuitting, !threads.isHeldTogether(name), let thread = threads.thread(name),
            let outcome = thread.outcome,
            thread.state != .merged, thread.state != .merging
        else { return }
        if threads.hasUnmerged(under: name) {
            threads.setState(name, .held)
            update(.runners(threads.runners))
            return
        }
        if outcome != .done {
            threads.setState(name, .waitingForApproval)
            update(.runners(threads.runners))
            let what = outcome == .failed ? "failed" : "was stopped"
            let into = thread.parent ?? "main"
            let merging = await confirm(
                "\(name) \(what). Merge it back into \(into), with a summary of what it did?",
                update: { update(.thread(id: name, $0)) }
            )
            guard merging else {
                threads.setState(name, outcome)
                update(.runners(threads.runners))
                return
            }
        }
        await merge(thread, update: update)
    }

    /// Stops thread `name` and every thread under it (roadmap 0195), then asks once, in its lane, whether to merge them back in. Yes
    /// merges them from the bottom up; no leaves them stopped, unmerged, to go on with or merge later.
    func stopThread(_ name: String, update: @escaping @Sendable (ConversationUpdate) -> Void) async {
        let group = threads.subtree(name)
        guard let root = threads.thread(name) else { return }
        await threads.stop(group, holding: true)
        defer { threads.release(group) }
        update(.runners(threads.runners))
        let others = group.count - 1
        let what =
            others == 0
            ? "\(name) was stopped" : "\(name) and its \(others) thread\(others == 1 ? "" : "s") were stopped"
        let merging = await confirm(
            "\(what). Merge \(others == 0 ? "it" : "them") back into \(root.parent ?? "main"), with a summary of what "
                + "\(others == 0 ? "it" : "each") did?",
            update: { update(.thread(id: name, $0)) }
        )
        guard merging else { return }
        // Each before the thread it is under: the reverse of the subtree's order.
        for member in group.reversed() {
            guard let thread = threads.thread(member), thread.state != .merged else { continue }
            await merge(thread, settlingParent: member == name, update: update)
        }
    }

    /// Writes thread's summary, gives it to its parent with a block there, closes it, and settles the parent.
    private func merge(
        _ thread: ThreadTable.Thread,
        settlingParent: Bool = true,
        update: @escaping @Sendable (ConversationUpdate) -> Void
    ) async {
        let name = thread.name
        threads.setState(name, .merging)
        update(.runners(threads.runners))
        let merged = threads.takeReports(for: name)
        let question = merged.isEmpty ? "" : "What the threads merged into this one reported:" + merged.joined()
        var summary: String
        do {
            let loop = try agentLoop()
            let written = try await loop.aside(
                question,
                over: thread.recorder.tree,
                instruction: AgentLoop.mergeInstruction
            )
            usage.withLock { $0.addBeside(written.usage) }
            update(.status(usage.withLock { $0.compact }))
            summary = written.answer
        } catch {
            update(
                .thread(
                    id: name,
                    .notice(
                        "\(name) could not write its summary: \(error). Its last reply goes instead.",
                        isError: true
                    )
                )
            )
            summary = ""
        }
        if summary.allSatisfy(\.isWhitespace) {
            summary = (Self.lastAnswer(in: thread.recorder.tree) ?? "") + merged.joined()
        }
        threads.setState(name, .merged)
        recordMerged(name, summary: summary, into: thread.parent.flatMap { threads.thread($0)?.recorder })
        threads.addReport(Self.report(name, summary), to: thread.parent)
        let block = ConversationUpdate.threadMerged(
            id: "merge-\(name)",
            name: name,
            prompt: thread.prompt,
            summary: summary
        )
        update(thread.parent.map { .thread(id: $0, block) } ?? block)
        update(.runners(threads.runners))
        if settlingParent, let parent = thread.parent { await settle(parent, update: update) }
    }

    /// The text of the last reply in `tree`, nil when it has none.
    static func lastAnswer(in tree: SessionTree) -> String? {
        for entry in tree.context().reversed() {
            guard case .response(let response, _) = entry.payload else { continue }
            let text = response.blocks.compactMap { if case .text(let text) = $0 { text } else { nil } }
                .joined(separator: "\n")
            if !text.allSatisfy(\.isWhitespace) { return text }
        }
        return nil
    }

    static func report(_ name: String, _ summary: String) -> String {
        "\(ListReferences.threadMarker)\(name) ---\n\(summary)\n--- end of thread ---"
    }
}
