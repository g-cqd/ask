internal import Foundation
internal import Testing

@testable import AskAI

/// The Responses decoder on the event shapes OpenAI documents and pi decodes: summaries, `output_index`, encrypted
/// reasoning and `response.incomplete`, none of which llama.cpp's recordings contain (those are replayed in
/// ``ResponsesReplayTests``). Frames are built by hand so each case states exactly what the server said.
@Suite("The Responses decoder turns items and their deltas into neutral blocks")
struct ResponsesStreamDecoderTests {
    private static let created =
        #"{"type":"response.created","response":{"id":"resp_1","model":"gpt-x","status":"in_progress"}}"#

    private func decode(_ frames: [String], finish: Bool = true) throws -> [ModelEvent] {
        var decoder = ResponsesStreamDecoder()
        var events: [ModelEvent] = []
        for frame in frames { try decoder.decode(SSEEvent(name: "message", data: Array(frame.utf8)), into: &events) }
        if finish { try decoder.finish(into: &events) }
        return events
    }

    private func completed(
        _ extra: String = #""output":[]"#, usage: String = #""usage":{"input_tokens":10,"output_tokens":4}"#
    )
        -> String
    { #"{"type":"response.completed","response":{"status":"completed",\#(extra),\#(usage)}}"# }

    @Test func `a message streams as one text block, with usage and the end of turn`() throws {
        let events = try decode([
            Self.created,
            #"{"type":"response.output_item.added","output_index":0,"item":{"type":"message","id":"msg_1","role":"assistant","content":[]}}"#,
            #"{"type":"response.content_part.added","item_id":"msg_1","part":{"type":"output_text","text":""}}"#,
            #"{"type":"response.output_text.delta","item_id":"msg_1","output_index":0,"delta":"Hel"}"#,
            #"{"type":"response.output_text.delta","item_id":"msg_1","output_index":0,"delta":"lo"}"#,
            #"{"type":"response.output_text.done","item_id":"msg_1","text":"Hello"}"#,
            #"{"type":"response.output_item.done","item":{"type":"message","id":"msg_1","role":"assistant"}}"#,
            completed(
                usage: #""usage":{"input_tokens":10,"output_tokens":4,"input_tokens_details":{"cached_tokens":6}}"#)
        ])
        #expect(
            events == [
                .messageStarted(id: "resp_1", model: "gpt-x", usage: TokenUsage()), .blockStarted(index: 0, .text),
                .textDelta(index: 0, "Hel"), .textDelta(index: 0, "lo"), .blockStopped(index: 0),
                .messageDelta(stopReason: .endTurn, usage: TokenUsage(input: 4, output: 4, cacheRead: 6)),
                .messageStopped
            ])
    }

    @Test func `reasoning with encrypted content carries a marked signature, summary parts as paragraphs`() throws {
        let events = try decode([
            Self.created,
            #"{"type":"response.output_item.added","item":{"type":"reasoning","id":"rs_1","summary":[]}}"#,
            #"{"type":"response.reasoning_summary_part.added","item_id":"rs_1","summary_index":0}"#,
            #"{"type":"response.reasoning_summary_text.delta","item_id":"rs_1","delta":"Plan"}"#,
            #"{"type":"response.reasoning_summary_part.added","item_id":"rs_1","summary_index":1}"#,
            #"{"type":"response.reasoning_summary_text.delta","item_id":"rs_1","delta":"Act"}"#,
            #"{"type":"response.output_item.done","item":{"type":"reasoning","id":"rs_1","summary":[{"type":"summary_text","text":"Plan"},{"type":"summary_text","text":"Act"}],"encrypted_content":"enc"}}"#,
            completed()
        ])
        let payload =
            #"{"type":"reasoning","id":"rs_1","summary":[{"type":"summary_text","text":"Plan"},{"type":"summary_text","text":"Act"}],"encrypted_content":"enc"}"#
        #expect(events[1] == .blockStarted(index: 0, .thinking))
        #expect(events[2] == .thinkingDelta(index: 0, "Plan"))
        #expect(events[3] == .thinkingDelta(index: 0, "\n\n"))
        #expect(events[4] == .thinkingDelta(index: 0, "Act"))
        #expect(events[5] == .signatureDelta(index: 0, ReasoningProvenance.mark(scheme: "responses", payload: payload)))
        #expect(events[6] == .blockStopped(index: 0))
    }

    @Test func `reasoning with no encrypted content has no signature, and with no text no block`() throws {
        let events = try decode([
            Self.created,
            #"{"type":"response.output_item.added","item":{"type":"reasoning","id":"rs_1","summary":[]}}"#,
            #"{"type":"response.output_item.done","item":{"type":"reasoning","id":"rs_1","summary":[],"encrypted_content":""}}"#,
            completed()
        ])
        #expect(events.allSatisfy { if case .blockStarted = $0 { false } else { true } })
        #expect(events.allSatisfy { if case .signatureDelta = $0 { false } else { true } })
    }

    @Test func `a function call is a tool block keyed by its call id, and ends the turn as tool use`() throws {
        let events = try decode([
            Self.created,
            #"{"type":"response.output_item.added","item":{"type":"function_call","id":"fc_1","call_id":"call_9","name":"read","arguments":""}}"#,
            #"{"type":"response.function_call_arguments.delta","item_id":"fc_1","delta":"{\"path\":"}"#,
            #"{"type":"response.function_call_arguments.delta","item_id":"fc_1","delta":"\"a\"}"}"#,
            #"{"type":"response.function_call_arguments.done","item_id":"fc_1","arguments":"{\"path\":\"a\"}"}"#,
            #"{"type":"response.output_item.done","item":{"type":"function_call","id":"fc_1","call_id":"call_9","name":"read","arguments":"{\"path\":\"a\"}"}}"#,
            completed(#""output":[{"type":"function_call","id":"fc_1"}]"#)
        ])
        #expect(events[1] == .blockStarted(index: 0, .toolUse(id: "call_9", name: "read")))
        #expect(events[2] == .toolInputDelta(index: 0, #"{"path":"#))
        #expect(events[3] == .toolInputDelta(index: 0, #""a"}"#))
        #expect(events[4] == .blockStopped(index: 0))
        if case .messageDelta(let reason, _) = events[5] {
            #expect(reason == .toolUse)
        } else {
            Issue.record("no stop")
        }
    }

    @Test func `arguments sent only in the finished item are not lost`() throws {
        let events = try decode([
            Self.created,
            #"{"type":"response.output_item.added","item":{"type":"function_call","id":"fc_1","call_id":"c","name":"read","arguments":""}}"#,
            #"{"type":"response.output_item.done","item":{"type":"function_call","id":"fc_1","call_id":"c","name":"read","arguments":"{\"a\":1}"}}"#,
            completed(#""output":[{"type":"function_call"}]"#)
        ])
        #expect(events.contains(.toolInputDelta(index: 0, #"{"a":1}"#)))
    }

    @Test func `a whitespace-only message makes no block, as with chat completions`() throws {
        let events = try decode([
            Self.created,
            #"{"type":"response.output_item.added","item":{"type":"message","id":"msg_1","role":"assistant"}}"#,
            #"{"type":"response.output_text.delta","item_id":"msg_1","delta":"\n\n"}"#,
            #"{"type":"response.output_item.done","item":{"type":"message","id":"msg_1"}}"#,
            completed()
        ])
        #expect(events.allSatisfy { if case .blockStarted = $0 { false } else { true } })
    }

    @Test func `a message whose text only arrives in the finished item still shows it`() throws {
        let events = try decode([
            Self.created,
            #"{"type":"response.output_item.added","item":{"type":"message","id":"msg_1","role":"assistant"}}"#,
            #"{"type":"response.output_item.done","item":{"type":"message","id":"msg_1","content":[{"type":"output_text","text":"Whole"}]}}"#,
            completed()
        ])
        #expect(events.contains(.textDelta(index: 0, "Whole")))
    }
}
