internal import Foundation
internal import Testing

@testable import AskAI

/// How a Responses stream ends, and fails: the terminal events, their stop reasons and the errors inside the stream.
@Suite("A Responses stream ends as completed, incomplete or failed, and says why")
struct ResponsesStreamEndingTests {
    private static let created = #"{"type":"response.created","response":{"id":"r","model":"m"}}"#

    private func decode(_ frames: [String], finish: Bool = true) throws -> [ModelEvent] {
        var decoder = ResponsesStreamDecoder()
        var events: [ModelEvent] = []
        for frame in frames { try decoder.decode(SSEEvent(name: "message", data: Array(frame.utf8)), into: &events) }
        if finish { try decoder.finish(into: &events) }
        return events
    }

    private func stopReason(_ events: [ModelEvent]) -> StopReason? {
        for case .messageDelta(let reason, _) in events { return reason }
        return nil
    }

    @Test(arguments: [
        ("max_output_tokens", StopReason.maxTokens), ("content_filter", .refusal),
        ("something_new", .other("something_new"))
    ])
    func `an incomplete response says why it stopped`(reason: String, expected: StopReason) throws {
        let events = try decode([
            Self.created,
            #"{"type":"response.incomplete","response":{"status":"incomplete","incomplete_details":{"reason":"\#(reason)"},"usage":{"input_tokens":5,"output_tokens":9}}}"#
        ])
        #expect(stopReason(events) == expected)
        #expect(events.last == .messageStopped)
    }

    @Test func `a stream that never ends in a terminal event is unfinished, not complete`() {
        #expect(throws: OpenAIStreamError.unfinished) {
            _ = try decode([Self.created, #"{"type":"response.output_text.delta","item_id":"m","delta":"half"}"#])
        }
    }

    @Test func `a failed response is the provider's failure, with its kind and window`() {
        let frame =
            #"{"type":"response.failed","response":{"status":"failed","error":{"code":"context_length_exceeded","message":"Your input exceeds the context window of this model."}}}"#
        do {
            _ = try decode([Self.created, frame])
            Issue.record("a failed response decoded")
        } catch OpenAIStreamError.provider(let failure) {
            #expect(failure.kind == .contextOverflow)
            #expect(failure.message.contains("context window"))
        } catch { Issue.record("\(error)") }
    }

    @Test func `an error event is the provider's failure`() {
        do {
            _ = try decode([#"{"type":"error","code":"rate_limit_exceeded","message":"Slow down"}"#])
            Issue.record("an error decoded")
        } catch OpenAIStreamError.provider(let failure) {
            #expect(failure.kind == .rateLimited)
            #expect(failure.message == "Slow down")
        } catch { Issue.record("\(error)") }
    }

    @Test func `an event that is not JSON is malformed`() {
        #expect(throws: OpenAIStreamError.malformed) { _ = try decode(["not json"], finish: false) }
    }

    @Test func `an event nobody knows is reported, and the known quiet ones are not`() throws {
        let events = try decode([
            Self.created, #"{"type":"response.in_progress","response":{"id":"r"}}"#,
            #"{"type":"response.content_part.added","item_id":"m","part":{"type":"output_text","text":""}}"#,
            #"{"type":"response.brand_new","x":1}"#,
            #"{"type":"response.completed","response":{"status":"completed"}}"#
        ])
        #expect(events.contains(.unrecognized(event: "message", type: "response.brand_new")))
        #expect(events.filter { if case .unrecognized = $0 { true } else { false } }.count == 1)
    }

    @Test func `an item type nobody knows is kept as an unrecognised block, not dropped`() throws {
        let events = try decode([
            Self.created, #"{"type":"response.output_item.added","item":{"type":"web_search_call","id":"ws_1"}}"#,
            #"{"type":"response.output_item.done","item":{"type":"web_search_call","id":"ws_1"}}"#,
            #"{"type":"response.completed","response":{"status":"completed"}}"#
        ])
        #expect(events.contains(.blockStarted(index: 0, .unrecognized(type: "web_search_call"))))
        #expect(events.contains(.blockStopped(index: 0)))
    }

    @Test func `a refusal streams as text and ends the turn as a refusal`() throws {
        let events = try decode([
            Self.created, #"{"type":"response.output_item.added","item":{"type":"message","id":"m"}}"#,
            #"{"type":"response.refusal.delta","item_id":"m","delta":"I can't help with that."}"#,
            #"{"type":"response.output_item.done","item":{"type":"message","id":"m"}}"#,
            #"{"type":"response.completed","response":{"status":"completed"}}"#
        ])
        #expect(events.contains(.textDelta(index: 0, "I can't help with that.")))
        #expect(stopReason(events) == .refusal)
    }

    @Test func `the error body of a refused request is read as OpenAI's, with the window it names`() {
        let body =
            #"{"error":{"code":400,"message":"request (40010 tokens) exceeds the available context size (8192 tokens), try increasing it","type":"exceed_context_size_error","n_prompt_tokens":40010,"n_ctx":8192}}"#
        let failure = ResponsesStreamDecoder.failure(inErrorBody: Array(body.utf8))
        #expect(failure?.kind == .contextOverflow)
        #expect(failure?.contextWindow == 8192)
    }
}
