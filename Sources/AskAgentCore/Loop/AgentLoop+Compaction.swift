internal import AskAI

/// Compaction in the loop (roadmap 0030): summarise the context before the kept tail and record it.
extension AgentLoop {
    /// Whether to compact before the next request: the window is full, or the context reached the threshold.
    /// Synchronous and O(1) in the common case, since it runs before every request.
    func compactionDue(_ session: SessionRecorder, contextFull: Bool) -> Bool {
        if contextFull { return true }
        guard let threshold = settings.compactAtTokens else { return false }
        return (session.reading { Compaction.contextTokens(sinceCompactionIn: $0) } ?? 0) >= threshold
    }

    /// Compacts the session's context.
    ///
    /// A threshold compaction that fails is reported and skipped: the run goes on with the whole context. A
    /// full window cannot go on without one, so its failure ends the run.
    /// - Throws: ``AgentError``, only when `contextFull` or on abort.
    func compact(_ session: SessionRecorder, contextFull: Bool, events: (AgentEvent) -> Void)
        async throws(AgentError)
    {
        do {
            let (summary, usage, firstKept) = try await summarise(session.tree.context(), events: events)
            try record(.compaction(summary: summary, firstKept: firstKept), in: session)
            events(.compacted(summary: summary, usage: usage))
        } catch {
            if contextFull || error == .cancelled { throw error }
            events(.compactionFailed(String(describing: error)))
        }
    }

    /// One summarisation request: the context as last sent, then the instruction. Only retries are reported;
    /// the summary is ask's own request and is not shown as the assistant speaking.
    private func summarise(_ context: [SessionEntry], events: (AgentEvent) -> Void) async throws(AgentError)
        -> (summary: String, usage: TokenUsage, firstKept: EntryID)
    {
        guard let cut = Compaction.cut(context, keepingRecentBytes: settings.keepRecentBytes) else {
            throw .provider("nothing before the recent messages to summarise")
        }
        var request = request(for: context) { _ in }
        if request.messages.last?.role == .user {
            request.messages[request.messages.count - 1].blocks.append(.text(Compaction.instruction))
        } else {
            request.messages.append(ModelMessage(role: .user, blocks: [.text(Compaction.instruction)]))
        }
        let response = try await stream(request) { event in
            if case .retrying = event { events(event) }
        }
        let summary = response.blocks
            .compactMap { block -> String? in
                guard case .text(let text) = block else { return nil }
                return text
            }
            .joined(separator: "\n")
        guard !summary.allSatisfy(\.isWhitespace) else { throw .provider("the summary came back empty") }
        return (summary, response.usage, context[cut].id)
    }
}
