import AemiJSON
import AskAI
import Testing

@testable import AskAgentCore

/// Light compaction (roadmap 0032, the owner's choice of 2026-11-12): once the context reaches the trigger, a tool's old output and
/// earlier reasoning before the kept tail leave the request; the session keeps them, and every request after reaches as far.
@Suite("Old tool output and reasoning are cleared before the kept tail")
struct ContextClearingTests {
    private static let big = String(repeating: "x", count: 40_000)

    /// A call with reasoning, its result, `rounds` times; the last response reports `tokens`.
    private func context(rounds: Int, tokens: Int, compactedFirst: Bool = false) throws -> [SessionEntry] {
        let input = try JSONObject(validating: Array("{}".utf8))
        var payloads: [SessionPayload] = compactedFirst ? [] : [.user("start")]
        for round in 0 ..< rounds {
            let response = AssembledResponse(
                id: "m\(round)",
                model: "x",
                blocks: [
                    .thinking(text: "why \(round)", signature: "sig\(round)"),
                    .toolCall(id: "t\(round)", name: "bash", input: input)
                ],
                stopReason: .toolUse,
                usage: TokenUsage(input: round == rounds - 1 ? tokens : 1_000),
                unrecognized: []
            )
            payloads += [.response(response), .toolResult(callID: "t\(round)", content: Self.big, isError: false)]
        }
        var entries: [SessionEntry] = []
        if compactedFirst {
            // A compaction's kept entries come before the new ones; theirs are sizes from before it.
            entries.append(
                SessionEntry(
                    id: EntryID("c"),
                    parentID: nil,
                    payload: .compaction(summary: "s", firstKept: EntryID("e0"))
                )
            )
        }
        for (offset, payload) in payloads.enumerated() {
            entries.append(
                SessionEntry(
                    id: EntryID("e\(offset)"),
                    parentID: offset == 0 ? nil : EntryID("e\(offset - 1)"),
                    payload: payload
                )
            )
        }
        return entries
    }

    @Test func `below the trigger nothing is cleared`() throws {
        #expect(
            ContextClearing.reach(in: try context(rounds: 8, tokens: 50_000), at: 90_000, keepingRecentBytes: 100_000)
                == nil
        )
    }

    @Test func `at the trigger, old output becomes a line and old reasoning leaves; the tail is whole`() throws {
        let entries = try context(rounds: 8, tokens: 95_000)
        let reach = try #require(ContextClearing.reach(in: entries, at: 90_000, keepingRecentBytes: 100_000))
        #expect(reach > 1 && reach < entries.count - 2)
        let messages = RequestContext(entries, clearingBefore: reach).messages
        let results = messages.flatMap(\.blocks)
            .compactMap { block -> String? in
                if case .toolResult(_, let content, _, _) = block { return content }
                return nil
            }
        #expect(results.count == 8)
        #expect(results.first?.hasPrefix("[ask left this output out") == true)
        #expect(results.last == Self.big, "the kept tail's output is whole")
        let thinking = messages.flatMap(\.blocks).filter { if case .thinking = $0 { true } else { false } }
        #expect(thinking.count < 8 && !thinking.isEmpty, "earlier reasoning leaves, the latest stays")
        #expect(RequestContext(entries).messages != messages, "without a reach the request is as before")
    }

    @Test func `a clearing that frees too little is not made, so the cache is not broken for it`() throws {
        let entries = try context(rounds: 2, tokens: 95_000)
        #expect(ContextClearing.reach(in: entries, at: 90_000, keepingRecentBytes: 30_000) == nil)
    }

    @Test func `the sizes a compaction kept from before it do not trigger a clearing`() throws {
        var entries = try context(rounds: 8, tokens: 95_000, compactedFirst: true)
        // Only the kept entries, none new: their 95,000 is the size before the compaction.
        entries = entries.map {
            $0.id == EntryID("e0") ? SessionEntry(id: $0.id, parentID: EntryID("x"), payload: $0.payload) : $0
        }
        #expect(ContextClearing.reach(in: entries, at: 90_000, keepingRecentBytes: 100_000) == nil)
    }
}
