internal import AskAI
internal import AskAgentCore
internal import AskTUI
internal import Synchronization

/// A thread merges into its parent (roadmap 0195) only when the person runs `/merge` in its lane (note n52, the owner's choice of
/// 2026-11-07): it never merges on its own, and ask never asks. One request, like a compaction, writes the summary its parent receives in
/// place of what it did. A subagent alone merges by itself once its run ends (ADR-0146): its report is what the call that started it
/// waits for. Merges go from the bottom up: a subagent held by subagents under it is settled again when the last merges.
extension AgentConversation {
    /// Once thread `name`'s run has ended: a subagent merges if it is ready, or is held while one under it has not merged; a thread
    /// is left as its run ended, to go on with or to `/merge`. Nothing while ask quits: what it stopped stays unmerged.
    func settle(_ name: String, update: @escaping @Sendable (ConversationUpdate) -> Void) async {
        guard !threads.isQuitting, !threads.isHeldTogether(name), let thread = threads.thread(name),
            let outcome = thread.outcome,
            thread.state != .merged, thread.state != .merging
        else { return }
        guard threads.isSubagent(name) else {
            threads.setState(name, outcome)
            update(.runners(threads.runners))
            return
        }
        if threads.hasUnmerged(under: name) {
            threads.setState(name, .held)
            update(.runners(threads.runners))
            return
        }
        await merge(thread, update: update)
    }

    /// Stops thread `name` and every thread under it (roadmap 0195), and leaves them unmerged, to go on with or to `/merge` (note n52:
    /// ask does not ask); a subagent's are merged.
    func stopThread(_ name: String, update: @escaping @Sendable (ConversationUpdate) -> Void) async {
        let group = threads.subtree(name)
        guard threads.thread(name) != nil else { return }
        await threads.stop(group, holding: true)
        defer { threads.release(group) }
        update(.runners(threads.runners))
        // A subagent merges, as it would on its own: the call that started it waits for its report.
        if threads.isSubagent(name) { return await mergeTogether(group, update: update) }
        let others = group.count - 1
        let what =
            others == 0
            ? "\(name) was stopped" : "\(name) and its \(others) thread\(others == 1 ? "" : "s") were stopped"
        update(
            .thread(
                id: name,
                .notice("\(what). /merge here merges \(others == 0 ? "it" : "them") back in.", isError: false)
            )
        )
    }

    /// `/merge` (or `/close`) in thread `name`'s lane: merges it now with the unmerged threads under it, from the bottom up. A thread
    /// stopped and not merged back, or brought back by a resume, merges on nothing else. Refused while any of them works.
    func mergeThread(_ name: String, update: @escaping @Sendable (ConversationUpdate) -> Void) {
        Task { await mergeNow(name, update: update) }
    }

    private func mergeNow(_ name: String, update: @escaping @Sendable (ConversationUpdate) -> Void) async {
        let say: @Sendable (String, Bool) -> Void = { text, isError in
            update(.thread(id: name, .notice(text, isError: isError)))
        }
        guard let root = threads.thread(name) else { return }
        guard root.state != .merged else { return say("\(name) has merged already.", false) }
        let group = threads.subtree(name)
        let working = group.filter { threads.thread($0)?.state.isActive == true }
        guard working.isEmpty else {
            let which = working.joined(separator: ", ")
            return say(
                "\(which) \(working.count == 1 ? "is" : "are") still working. Stop \(working.count == 1 ? "it" : "them") "
                    + "first (Ctrl+C in its lane), or let it finish, then /merge.",
                true
            )
        }
        await threads.stop(group, holding: true)
        defer { threads.release(group) }
        await mergeTogether(group, update: update)
    }

    /// Merges `group` (a thread, then the threads under it, as ``ThreadTable/subtree(_:)`` gives them) from the bottom up: each before
    /// the thread it is under, the first last, which alone settles its parent.
    private func mergeTogether(_ group: [String], update: @escaping @Sendable (ConversationUpdate) -> Void) async {
        for member in group.reversed() {
            guard let thread = threads.thread(member), thread.state != .merged else { continue }
            await merge(thread, settlingParent: member == group.first, update: update)
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
            // A subagent writes its summary on its own loop: its definition's model, as it worked.
            let loop =
                try await threads.isSubagent(name) ? subagentLoop(for: threads.subagentDefinition(name)) : threadLoop()
            // threads.summaryInstructions, then what the thread.merge hook point adds.
            let point = ThreadMerge(name: name, parent: thread.parent)
            let added =
                [current.withLock { $0.settings.configuration.threads.value.summaryAddition }].compactMap { $0 }
                + (await loop.mergeInstructions(point))
            let addition = added.isEmpty ? nil : added.joined(separator: "\n\n")
            let written = try await loop.aside(
                question,
                over: thread.recorder.tree,
                instruction: AgentLoop.mergeInstruction(adding: addition)
            )
            usage.withLock { $0.addBeside(written.usage) }
            update(.status(usage.withLock { $0.compact }))
            summary = await loop.mergedSummary(point, written.answer)
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
        // A subagent's summary is its call's result; a thread's goes with what its parent is sent next.
        if !threads.report(name, summary) { threads.addReport(Self.report(name, summary), to: thread.parent) }
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
