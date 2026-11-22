import AskAI
import Testing

@testable import AskAgentCore

/// What each stretch between compactions cost (roadmap 0239): the entries up to each compaction since the one before, and the time
/// worked in it, without the person's time between turns.
@Suite("What the work between two compactions cost")
struct CompactionSpendTests {
    private static func response(_ output: Int) -> SessionPayload {
        .response(
            AssembledResponse(
                id: "r",
                model: "m",
                blocks: [],
                stopReason: nil,
                usage: TokenUsage(output: output),
                unrecognized: []
            )
        )
    }

    @Test func `each compaction ends a stretch, and the work after the last one is not a stretch yet`() throws {
        var tree = SessionTree()
        var kept = EntryID("none")
        for (payload, time) in [
            (SessionPayload.user("a"), 0), (Self.response(10), 2_000),
            (.toolResult(callID: "1", content: "", isError: false), 5_000),
            (Self.response(20), 6_000), (.user("b, the next morning"), 36_000_000), (Self.response(30), 36_004_000)
        ] {
            let id = try tree.append(payload, recordedAt: time)
            if time == 36_000_000 { kept = id }
        }
        _ = try tree.append(.compaction(summary: "s1", firstKept: kept), recordedAt: 36_005_000)
        _ = try tree.append(.user("c"), recordedAt: 36_010_000)
        _ = try tree.append(Self.response(400), recordedAt: 36_011_000)
        _ = try tree.append(.compaction(summary: "s2", firstKept: kept), recordedAt: 36_012_000)
        _ = try tree.append(Self.response(5_000), recordedAt: 36_013_000)
        let stretches = WorkSpend.compactionStretches(in: tree)
        #expect(stretches.map(\.requests) == [3, 1] && stretches.map(\.usage.output) == [60, 400])
        #expect(stretches.first?.toolCalls == 1)
        #expect(stretches.first?.wallMilliseconds == 36_004_000, "the wall clock spans the night")
        #expect(
            stretches.first?.workingMilliseconds == 10_000,
            "2 s, 3 s of tool, 1 s, then 4 s: the night is the person's"
        )
        #expect(WorkSpend.compactionStretches(in: SessionTree()).isEmpty)
    }
}
