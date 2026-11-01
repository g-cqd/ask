import AskAI
import Foundation
import Testing

@testable import AskAgentCore

/// What a tool did, as typed facts beside its prose (roadmap 0078): an edit's replacement count reaches the header live and
/// after a resume, and is never parsed from the sentence the model reads.
@Suite("A tool's typed facts are recorded, replayed and kept apart from its output")
struct ToolFactsTests {
    private let facts = ToolFacts(replacements: 3)

    @Test func `facts survive the session file, and a result written before them reads as none`() throws {
        let payload = SessionPayload.toolResult(callID: "t1", content: "Replaced 3.", isError: false, facts: facts)
        let bytes = try JSONEncoder().encode(WirePayload(value: payload))
        #expect(try JSONDecoder().decode(WirePayload.self, from: bytes).value == payload)
        let older = Data(#"{"kind":"tool_result","callID":"t1","content":"ok","isError":false}"#.utf8)
        #expect(
            try JSONDecoder().decode(WirePayload.self, from: older).value
                == .toolResult(callID: "t1", content: "ok", isError: false)
        )
        let plain = try JSONEncoder()
            .encode(
                WirePayload(value: .toolResult(callID: "t1", content: "ok", isError: false))
            )
        #expect(!String(decoding: plain, as: UTF8.self).contains("replacements"), "no key when there is no fact")
    }

    /// A call to edit and its result with ``facts``, as a session records them.
    private func recorded() throws -> [SessionEntry] {
        let input = try JSONObject(validating: Array(#"{"path":"a"}"#.utf8))
        let asked = AssembledResponse(
            id: "m",
            model: "x",
            blocks: [.toolCall(id: "t1", name: "edit", input: input)],
            stopReason: .toolUse,
            usage: TokenUsage(output: 1),
            unrecognized: []
        )
        let payloads: [SessionPayload] = [
            .user("Go"), .response(asked),
            .toolResult(callID: "t1", content: "Replaced 3.", isError: false, facts: facts)
        ]
        return payloads.enumerated()
            .map { index, payload in
                SessionEntry(
                    id: EntryID("e\(index)"),
                    parentID: index == 0 ? nil : EntryID("e\(index - 1)"),
                    payload: payload
                )
            }
    }

    @Test func `a resumed session gives the screen the recorded facts`() throws {
        var expected = ToolOutput("Replaced 3.")
        expected.facts = facts
        #expect(
            SessionReplay.steps(try recorded())
                .contains(.event(.toolFinished(id: "t1", name: "edit", output: expected)))
        )
    }

    @Test func `facts stay out of what the model is sent`() throws {
        #expect(
            RequestContext(try recorded()).messages.last
                == ModelMessage(role: .user, blocks: [.toolResult(id: "t1", content: "Replaced 3.", isError: false)])
        )
    }
}
