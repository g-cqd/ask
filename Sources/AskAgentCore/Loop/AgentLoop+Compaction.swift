internal import AskAI

/// Compaction in the loop (roadmap 0030): summarise the context before the kept tail and record it.
extension AgentLoop {
    /// Whether to compact before the next request: the window is full, or the context reached the threshold and
    /// something sits before the kept tail to summarise. Synchronous and O(1) in the common case, since it runs
    /// before every request: a small window floors the threshold (its margin leaves nothing of the window), so
    /// the tail check keeps a whole conversation that fits the tail from trying every turn.
    func compactionDue(_ session: SessionRecorder, contextFull: Bool) -> Bool {
        if contextFull { return true }
        guard let threshold = budget.compactAtTokens else { return false }
        return session.reading { tree in
            guard (Compaction.contextTokens(sinceCompactionIn: tree) ?? 0) >= threshold else { return false }
            return Compaction.hasContent(beforeTailIn: tree, keepingRecentBytes: budget.keepRecentBytes)
        }
    }

    /// Compacts now, at the user's request, whatever the context's size. A summary that cannot be made is reported
    /// as a ``AgentEvent/compactionFailed(_:)``, and the session is left whole.
    /// - Throws: ``AgentError/cancelled`` when aborted.
    public func compactNow(in session: SessionRecorder, events: (AgentEvent) -> Void) async throws(AgentError) {
        try await compact(session, contextFull: false, explicit: true, events: events)
    }

    /// Compacts the session's context.
    ///
    /// A threshold compaction with nothing before the kept tail is skipped: it has nothing to do, and a window
    /// whose threshold sits at the floor would otherwise announce its own no-op on every turn. An explicit
    /// compaction still reports it, because the user asked. A threshold compaction that fails is reported and
    /// skipped: the run goes on with the whole context. A full window cannot go on without one, so its failure
    /// ends the run.
    /// - Parameters:
    ///   - session: the session whose context is compacted.
    ///   - contextFull: the window refused the request, so the compaction cannot be skipped.
    ///   - explicit: the user asked for this compaction, so "nothing to summarise" is reported rather than
    ///     skipped.
    ///   - events: where completed steps are reported.
    /// - Throws: ``AgentError``, only when `contextFull` or on abort.
    func compact(
        _ session: SessionRecorder, contextFull: Bool, explicit: Bool = false, events: (AgentEvent) -> Void
    ) async throws(AgentError) {
        let context = session.tree.context()
        if !contextFull, !explicit, Compaction.cut(context, keepingRecentBytes: budget.keepRecentBytes) == nil {
            return
        }
        do {
            let (summary, usage, firstKept) = try await summarise(context, contextFull: contextFull, events: events)
            try record(.compaction(summary: summary, firstKept: firstKept), in: session)
            events(.compacted(summary: summary, usage: usage))
        } catch {
            if contextFull || error == .cancelled { throw error }
            events(.compactionFailed(String(describing: error)))
        }
    }

    /// One summarisation request: the context as last sent, then the instruction. Only retries are reported;
    /// the summary is ask's own request and is not shown as the assistant speaking.
    /// Each tool result in a summary request that had to be made smaller keeps at most this much of its output.
    static var clippedResultBytes: Int { 4_096 }

    /// Asks the model to summarise everything before the kept tail.
    ///
    /// The first request is the context as last sent plus the instruction, so the provider reads it from its cache
    /// (ADR-0026). When that is refused for its length, the request is made again with only the part being replaced
    /// and each tool output in it clipped: the summary covers that part alone, and a small window can hold it. When the
    /// model writes no summary, a mechanical record of the part takes its place (``Compaction/record(of:)``).
    /// - Parameters:
    ///   - context: the context as the tree gives it.
    ///   - contextFull: the compaction cannot be skipped, so the kept tail shrinks if it would leave nothing.
    ///   - events: where retries are reported.
    /// - Returns: the summary, the usage of the request that made it, and the first entry kept word for word.
    /// - Throws: ``AgentError`` when there is nothing to summarise or the requests fail.
    private func summarise(_ context: [SessionEntry], contextFull: Bool, events: (AgentEvent) -> Void)
        async throws(AgentError) -> (summary: String, usage: TokenUsage, firstKept: EntryID)
    {
        let tail = budget.keepRecentBytes
        guard
            let cut = Compaction.cut(context, keepingRecentBytes: tail)
                ?? (contextFull ? Compaction.cut(context, keepingAtMost: tail) : nil)
        else { throw .provider("nothing before the recent messages to summarise") }
        let response: AssembledResponse
        do {
            response = try await summaryResponse(for: context, events: events)
        } catch .contextOverflow {
            let older = Compaction.clippingResults(context[..<cut], toBytes: Self.clippedResultBytes)
            response = try await summaryResponse(for: older, events: events)
        }
        let text = Self.joined(response.blocks) { if case .text(let text) = $0 { text } else { nil } }
        // No summary from the model, as a reasoning model out of reply budget does: record the part instead.
        let summary = !text.allSatisfy(\.isWhitespace) ? text : Compaction.record(of: context[..<cut])
        return (summary, response.usage, context[cut].id)
    }

    /// The model's reply to `entries` followed by the summary instruction.
    private func summaryResponse(for entries: [SessionEntry], events: (AgentEvent) -> Void)
        async throws(AgentError) -> AssembledResponse
    {
        var request = request(for: entries) { _ in }
        if request.messages.last?.role == .user {
            request.messages[request.messages.count - 1].blocks.append(.text(Compaction.instruction))
        } else {
            request.messages.append(ModelMessage(role: .user, blocks: [.text(Compaction.instruction)]))
        }
        return try await stream(request) { event in
            if case .retrying = event { events(event) }
        }
    }

    private static func joined(_ blocks: [ContentBlock], _ text: (ContentBlock) -> String?) -> String {
        blocks.compactMap(text).joined(separator: "\n")
    }
}
