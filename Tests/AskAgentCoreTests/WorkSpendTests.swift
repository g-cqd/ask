import AskAI
import Testing

@testable import AskAgentCore

/// What work cost is read from a session's entries (roadmap 0239): each response's tokens and model, each tool result, and the time
/// before each, the model's or the tools'.
@Suite("What work cost, read from the entries")
struct WorkSpendTests {
    private static func response(_ model: String, _ usage: TokenUsage) -> SessionPayload {
        .response(AssembledResponse(id: "r", model: model, blocks: [], stopReason: nil, usage: usage, unrecognized: []))
    }

    private static func entry(_ payload: SessionPayload, at time: Int?) -> SessionEntry {
        SessionEntry(id: EntryID("e"), parentID: nil, payload: payload, recordedAt: time)
    }

    /// A turn: a prompt at 0, a response at 2 s calling two tools, results at 5 s and 6 s, the last response at 10 s.
    private static let turn = [
        entry(.user("go"), at: 1_000),
        entry(response("model-a", TokenUsage(input: 10, output: 100, cacheRead: 5_000)), at: 3_000),
        entry(.toolResult(callID: "1", content: "", isError: false), at: 6_000),
        entry(.toolResult(callID: "2", content: "", isError: false), at: 7_000),
        entry(response("model-b", TokenUsage(input: 20, output: 50, cacheRead: 6_000, cacheCreation: 300)), at: 11_000)
    ]

    @Test func `a turn's requests, tokens, tool calls and models`() {
        let spend = WorkSpend(of: Self.turn)
        #expect(spend.requests == 2 && spend.toolCalls == 2)
        #expect(spend.usage == TokenUsage(input: 30, output: 150, cacheRead: 11_000, cacheCreation: 300))
        #expect(spend.models == ["model-a", "model-b"])
    }

    @Test func `its time: the whole, the model's before each response, the tools' before each result`() {
        let spend = WorkSpend(of: Self.turn)
        #expect(spend.wallMilliseconds == 10_000)
        #expect(spend.modelMilliseconds == 2_000 + 4_000)
        #expect(spend.toolMilliseconds == 3_000 + 1_000)
    }

    @Test func `entries an older ask wrote have tokens but no time, and a kind never reported stays unknown`() {
        let spend = WorkSpend(of: Self.turn.map { Self.entry($0.payload, at: nil) })
        #expect(
            spend.requests == 2 && spend.wallMilliseconds == nil && spend.modelMilliseconds == nil
                && spend.toolMilliseconds == nil
        )
        let partial = WorkSpend(of: [Self.entry(Self.response("m", TokenUsage(output: 7)), at: nil)])
        #expect(partial.usage == TokenUsage(output: 7), "input never reported is nil, not zero")
        #expect(partial.compactTokens == "↓7", "and not said as ↑0")
        #expect(WorkSpend(of: [Self.entry(Self.response("m", TokenUsage(input: 3)), at: nil)]).compactTokens == "↑3")
    }

    @Test func `two spends add up, each model once`() {
        let one = WorkSpend(of: Self.turn)
        let two = one + WorkSpend(of: Array(Self.turn.prefix(2)))
        #expect(two.requests == 3 && two.toolCalls == 2 && two.usage.output == 250)
        #expect(two.wallMilliseconds == 12_000 && two.models == ["model-a", "model-b"])
        #expect(WorkSpend().isEmpty && !one.isEmpty)
    }

    @Test func `a response left in the file keeps what it cost, so nothing is read back for it`() throws {
        let entry = Self.entry(Self.response("m", TokenUsage(input: 1, output: 2)), at: 5)
        #expect(entry.spent?.usage == TokenUsage(input: 1, output: 2) && entry.spent?.model == "m")
        #expect(entry.reparented(to: nil).spent?.model == "m")
        #expect(Self.entry(.user("x"), at: 5).spent == nil)
    }
}
