import AskAI
import Testing

@testable import AskAgentCore

/// Replaying a recorded session gives the screen the same events a live run would have, so a resumed
/// conversation looks the way it did, through the same code that showed it the first time.
@Suite("A recorded session replays as the events that produced it")
struct SessionReplayTests {
    private func response(_ blocks: [ContentBlock], output: Int = 1) -> AssembledResponse {
        AssembledResponse(
            id: "m", model: "x", blocks: blocks, stopReason: .endTurn, usage: TokenUsage(output: output),
            unrecognized: [])
    }

    private func entries(_ payloads: [SessionPayload]) -> [SessionEntry] {
        payloads.enumerated()
            .map { index, payload in
                SessionEntry(
                    id: EntryID("e\(index)"), parentID: index == 0 ? nil : EntryID("e\(index - 1)"),
                    payload: payload)
            }
    }

    @Test func `prompts, text, tool calls and their results come back in the order they happened`() throws {
        let input = try JSONObject(validating: Array(#"{"path":"a"}"#.utf8))
        let asked = response([.text("Let me look."), .toolCall(id: "t1", name: "read", input: input)])
        let answered = response([.thinking(text: "hm", signature: "s"), .text("Done.")])
        let steps = SessionReplay.steps(
            entries([
                .user("What is in a?"), .response(asked),
                .toolResult(callID: "t1", content: "one\ntwo", isError: false),
                .response(answered)
            ]))
        #expect(
            steps == [
                .prompt("What is in a?"),
                .event(.model(.textDelta(index: 0, "Let me look."))),
                .event(.responded(asked)),
                .event(.toolStarted(id: "t1", name: "read", input: input)),
                .event(.toolFinished(id: "t1", name: "read", output: ToolOutput("one\ntwo"))),
                .event(.model(.textDelta(index: 1, "Done."))),
                .event(.responded(answered))
            ])
    }

    @Test func `a call the run never answered replays as interrupted, and ask's continuation as a notice`() throws {
        let input = try JSONObject(validating: Array("{}".utf8))
        let asked = response([.toolCall(id: "t1", name: "bash", input: input)])
        let steps = SessionReplay.steps(entries([.user("Go."), .response(asked), .user(AgentLoop.continuationPrompt)]))
        #expect(
            steps == [
                .prompt("Go."),
                .event(.responded(asked)),
                .event(.toolStarted(id: "t1", name: "bash", input: input)),
                .event(
                    .toolFinished(
                        id: "t1", name: "bash", output: ToolOutput(RequestContext.interruptedResult, isError: true))),
                .event(.continuedAtOutputLimit)
            ])
    }

    @Test func `a session that ended mid-tool, as a crash leaves it, replays the call as interrupted`() throws {
        let input = try JSONObject(validating: Array("{}".utf8))
        let asked = response([.toolCall(id: "t1", name: "bash", input: input)])
        let steps = SessionReplay.steps(entries([.user("Go."), .response(asked)]))
        #expect(
            steps.suffix(2) == [
                .event(.toolStarted(id: "t1", name: "bash", input: input)),
                .event(
                    .toolFinished(
                        id: "t1", name: "bash", output: ToolOutput(RequestContext.interruptedResult, isError: true)))
            ])
    }

    @Test func `routing inserted between a tool call and its result is invisible to replay and context`() {
        let asked = response([.toolCall(id: "call", name: "read", input: .empty)])
        let payloads: [SessionPayload] = [
            .user("Go"), .response(asked), .toolResult(callID: "call", content: "ok", isError: false)
        ]
        var routed = payloads
        routed.insert(
            .destination(
                SessionDestination(connectionID: "stable", authorizationID: "grant", name: "renamed", model: "model")),
            at: 2)
        #expect(SessionReplay.steps(entries(routed)) == SessionReplay.steps(entries(payloads)))
        #expect(RequestContext(entries(routed)) == RequestContext(entries(payloads)))
    }

    @Test func `a compaction replays as one, and its usage and a response's count toward the totals`() {
        let steps = SessionReplay.steps(entries([.user("Go."), .compaction(summary: "S", firstKept: EntryID("e0"))]))
        #expect(steps.last == .event(.compacted(summary: "S", usage: TokenUsage())))
        #expect(AgentEvent.compacted(summary: "S", usage: TokenUsage(output: 3)).usage == TokenUsage(output: 3))
        #expect(AgentEvent.responded(response([], output: 4)).usage == TokenUsage(output: 4))
        #expect(AgentEvent.continuedAtOutputLimit.usage == nil)
    }
}
