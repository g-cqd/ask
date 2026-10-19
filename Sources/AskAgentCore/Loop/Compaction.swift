internal import AskAI

/// The rules of compaction (roadmap 0030): when it is due, where the kept tail starts, and what the model is
/// asked for. The loop does the requesting and recording.
///
/// The summary is plain text in a `.compaction` entry. Anthropic's server-side compaction was probed
/// (diary 10): it returns a signed block whose readable summary, sent back as plain text, answered as well.
/// So one neutral path serves every provider, and the summary stays readable in the session file.
public enum Compaction {
    /// What the summarisation request adds after the conversation. The rest of the request is the context as
    /// last sent, so the provider reads it from cache.
    public static let instruction = """
        [ask] This conversation is about to be compacted: everything above will be replaced by your summary, \
        followed by the most recent messages. Write that summary now, for yourself, so you can continue the work \
        without the original messages. Include: the user's goals and constraints, in their words where it \
        matters; decisions made and why; files read or changed, with paths; commands run and what they showed; \
        exact identifiers, values and error messages that still matter; what is done, what is in progress, and \
        the next steps. Leave out ask's standing instructions and the project's instruction files: they are sent \
        with every request. Do not call tools. Reply with the summary only.
        """

    /// The context's size after the newest response, its prompt plus its reply, which the next request will
    /// carry. Nil when a compaction came after it: the responses a compaction keeps report sizes from before.
    /// Checked before every request, so it walks up from the leaf and stops at the first response or
    /// compaction, rather than building the branch: at 500 turns that was +41% on a turn (diary 10).
    /// - Parameter tree: the session.
    /// - Returns: input, cache-read, cache-write and output tokens of the newest response, or nil.
    static func contextTokens(sinceCompactionIn tree: borrowing SessionTree) -> Int? {
        let newest = tree.nearest { payload in
            switch payload {
                case .response, .compaction: true
                default: false
            }
        }
        guard case .response(let response) = newest?.payload else { return nil }
        let usage = response.usage
        return (usage.input ?? 0) + (usage.cacheRead ?? 0) + (usage.cacheCreation ?? 0) + (usage.output ?? 0)
    }

    /// Where the kept tail starts in `context`: far enough back to keep `bytes` of recent text, then back to
    /// a prompt or a response, so a tool result is never kept without the call that made it.
    /// - Parameters:
    ///   - context: the context as the tree gives it.
    ///   - bytes: how much recent text to keep.
    /// - Returns: the index of the first kept entry, or nil when nothing would be left to summarise.
    static func cut(_ context: [SessionEntry], keepingRecentBytes bytes: Int) -> Int? {
        var index = context.count
        var kept = 0
        while index > 0, kept < bytes {
            index -= 1
            kept += size(context[index].payload)
        }
        while index > 0, !startsATurn(context[index].payload) { index -= 1 }
        return index > 0 ? index : nil
    }

    private static func startsATurn(_ payload: SessionPayload) -> Bool {
        switch payload {
            case .user, .assistant, .response: true
            case .toolResult, .compaction: false
        }
    }

    /// The text an entry adds to the context, in UTF-8 bytes.
    private static func size(_ payload: SessionPayload) -> Int {
        switch payload {
            case .user(let text), .assistant(let text): return text.utf8.count
            case .toolResult(_, let content, _): return content.utf8.count
            case .compaction(let summary, _): return summary.utf8.count
            case .response(let response):
                return response.blocks.reduce(0) { total, block in
                    switch block {
                        case .text(let text): total + text.utf8.count
                        case .thinking(let text, _): total + text.utf8.count
                        case .toolCall(_, _, let input): total + input.bytes.count
                        default: total
                    }
                }
        }
    }
}
