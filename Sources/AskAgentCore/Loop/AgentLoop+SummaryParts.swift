internal import AskAI

/// A summary made in parts (ADR-0155), for a conversation too long for one summary request to hold what it replaces.
extension AgentLoop {
    /// What follows the instruction when the summary takes more than one request.
    static let partNote =
        "[ask] The conversation is too long to summarise in one request, so it is given in parts, oldest first. When this part "
        + "opens with a summary, that is the summary of the parts before it: yours replaces it as well, so keep everything in it "
        + "that still matters."

    /// How much of a conversation one summary request carries, in bytes: the window less the reply, at three bytes a token, which
    /// dense text reaches. With no window known, the default compaction threshold stands in for it; a refusal then halves the part.
    static func partBytes(window: Int?, reply: Int) -> Int {
        Swift.max(1, (window ?? AgentSettings.defaultCompactAtTokens) - reply) * 3
    }

    /// Summarises `older` in as many requests as it takes for each to fit the window.
    ///
    /// Each request carries the summary so far, then the next whole turns, and its answer is the summary so far for the next. A part
    /// that is refused for its length, by the server or before it is sent, is halved; a single turn that still cannot fit is recorded
    /// mechanically (``Compaction/record(of:)``), as is a part the model answers with no summary. So the conversation is always
    /// replaced by something, and a refusal costs the part it names and nothing else.
    /// - Parameters:
    ///   - older: the entries being replaced, as they are to be sent.
    ///   - instruction: what asks for the summary.
    ///   - events: where retries are reported.
    /// - Returns: the summary, and the usage of the requests that made it, added up.
    /// - Throws: ``AgentError`` when a request fails for anything but its length.
    func summariseInParts(_ older: [SessionEntry], instruction: String, events: (AgentEvent) -> Void)
        async throws(AgentError) -> (summary: String, usage: TokenUsage)
    {
        var bytes = Self.partBytes(window: knownWindow, reply: budget.maximumTokens)
        var start = older.startIndex
        var carried: String?
        var usage = TokenUsage()
        while start < older.endIndex {
            let end = Compaction.partEnd(older, from: start, holding: bytes)
            let part = older[start ..< end]
            let whole = start == older.startIndex && end == older.endIndex
            do {
                let response = try await summaryResponse(
                    to: request(for: Self.opened(part, with: carried), clearingBefore: nil) { _ in },
                    instruction: whole ? instruction : instruction + "\n\n" + Self.partNote,
                    events: events
                )
                usage = Self.sum(usage, response.usage)
                let text = Self.text(of: response)
                carried = !text.allSatisfy(\.isWhitespace) ? text : Self.joined(carried, Compaction.record(of: part))
            } catch .contextOverflow {
                let half = Compaction.size(of: part) / 2
                if Compaction.partEnd(older, from: start, holding: half) < end {
                    bytes = half
                    continue
                }
                // One turn, and no request can hold it.
                carried = Self.joined(carried, Compaction.record(of: part))
            }
            start = end
        }
        return (carried ?? "", usage)
    }

    /// `part`, after the summary of the parts before it when there is one, as a compaction is sent.
    private static func opened(_ part: ArraySlice<SessionEntry>, with carried: String?) -> [SessionEntry] {
        guard let carried, let first = part.first else { return Array(part) }
        let summary = SessionEntry(
            id: EntryID("ask-summary-so-far"),
            parentID: nil,
            payload: .compaction(summary: carried, firstKept: first.id)
        )
        return [summary] + part
    }

    private static func joined(_ carried: String?, _ record: String) -> String {
        carried.map { $0 + "\n\n" + record } ?? record
    }

    /// Two usages added, a count neither reported staying unreported.
    private static func sum(_ one: TokenUsage, _ other: TokenUsage) -> TokenUsage {
        func add(_ one: Int?, _ other: Int?) -> Int? { one == nil && other == nil ? nil : (one ?? 0) + (other ?? 0) }
        return TokenUsage(
            input: add(one.input, other.input),
            output: add(one.output, other.output),
            cacheRead: add(one.cacheRead, other.cacheRead),
            cacheCreation: add(one.cacheCreation, other.cacheCreation)
        )
    }
}
