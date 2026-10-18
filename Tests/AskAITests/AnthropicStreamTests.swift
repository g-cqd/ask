import Testing

@testable import AskAI

/// Anthropic Messages streaming events, decoded into provider-neutral model events. Fixtures follow the
/// event shapes in the official SDK's `RawMessageStreamEvent` types (`@anthropic-ai/sdk` 0.129.0).
@Suite("Anthropic stream events decode into model events")
struct AnthropicStreamTests {
    private func decode(_ lines: [String]) throws(AnthropicStreamError) -> [ModelEvent] {
        var sse = SSEDecoder()
        var frames: [SSEEvent] = []
        let bytes = Array(lines.joined(separator: "\n").utf8)
        do { try sse.feed(bytes.span, into: &frames) } catch { Issue.record("framing: \(error)") }
        let decoder = AnthropicStreamDecoder()
        var events: [ModelEvent] = []
        for frame in frames { try decoder.decode(frame, into: &events) }
        return events
    }

    private func frame(_ name: String, _ json: String) -> String { "event: \(name)\ndata: \(json)\n" }

    private var messageStart: String {
        frame(
            "message_start",
            #"{"type":"message_start","message":{"id":"msg_1","type":"message","role":"assistant","#
                + #""model":"claude-x","content":[],"stop_reason":null,"stop_sequence":null,"#
                + #""usage":{"input_tokens":25,"output_tokens":1,"cache_read_input_tokens":7,"#
                + #""cache_creation_input_tokens":null}}}"#)
    }

    @Test func `a text turn decodes start to stop`() throws {
        let events = try decode([
            messageStart,
            frame(
                "content_block_start",
                #"{"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}"#),
            frame("ping", #"{"type": "ping"}"#),
            frame(
                "content_block_delta",
                #"{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hel"}}"#),
            frame(
                "content_block_delta",
                #"{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"lo \"é\""}}"#),
            frame("content_block_stop", #"{"type":"content_block_stop","index":0}"#),
            frame(
                "message_delta",
                #"{"type":"message_delta","delta":{"stop_reason":"end_turn","stop_sequence":null},"usage":{"output_tokens":15}}"#
            ),
            frame("message_stop", #"{"type":"message_stop"}"#),
            ""
        ])
        #expect(
            events == [
                .messageStarted(id: "msg_1", model: "claude-x", usage: TokenUsage(input: 25, output: 1, cacheRead: 7)),
                .blockStarted(index: 0, .text),
                .textDelta(index: 0, "Hel"),
                .textDelta(index: 0, "lo \"é\""),
                .blockStopped(index: 0),
                .messageDelta(stopReason: .endTurn, usage: TokenUsage(output: 15)),
                .messageStopped
            ])
    }

    @Test func `a tool call streams its input as partial JSON`() throws {
        let events = try decode([
            frame(
                "content_block_start",
                #"{"type":"content_block_start","index":1,"content_block":{"type":"tool_use","id":"toolu_9","name":"read","input":{}}}"#
            ),
            frame(
                "content_block_delta",
                #"{"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":""}}"#),
            frame(
                "content_block_delta",
                #"{"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"{\"path\": \"a"}}"#
            ),
            frame(
                "content_block_delta",
                #"{"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":".swift\"}"}}"#
            ),
            frame("content_block_stop", #"{"type":"content_block_stop","index":1}"#),
            frame(
                "message_delta",
                #"{"type":"message_delta","delta":{"stop_reason":"tool_use"},"usage":{"output_tokens":40}}"#),
            ""
        ])
        #expect(
            events == [
                .blockStarted(index: 1, .toolUse(id: "toolu_9", name: "read")),
                .toolInputDelta(index: 1, ""),
                .toolInputDelta(index: 1, #"{"path": "a"#),
                .toolInputDelta(index: 1, #".swift"}"#),
                .blockStopped(index: 1),
                .messageDelta(stopReason: .toolUse, usage: TokenUsage(output: 40))
            ])
    }

    @Test func `thinking streams its text and then its signature`() throws {
        let events = try decode([
            frame(
                "content_block_start",
                #"{"type":"content_block_start","index":0,"content_block":{"type":"thinking","thinking":"","signature":""}}"#
            ),
            frame(
                "content_block_delta",
                #"{"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"Hmm"}}"#),
            frame(
                "content_block_delta",
                #"{"type":"content_block_delta","index":0,"delta":{"type":"signature_delta","signature":"sig=="}}"#),
            frame(
                "content_block_start",
                #"{"type":"content_block_start","index":1,"content_block":{"type":"redacted_thinking","data":"opaque"}}"#
            ),
            ""
        ])
        #expect(
            events == [
                .blockStarted(index: 0, .thinking), .thinkingDelta(index: 0, "Hmm"), .signatureDelta(index: 0, "sig=="),
                .blockStarted(index: 1, .redactedThinking(data: "opaque"))
            ])
    }

    @Test(arguments: [
        ("end_turn", StopReason.endTurn), ("max_tokens", .maxTokens), ("stop_sequence", .stopSequence),
        ("tool_use", .toolUse), ("pause_turn", .pauseTurn), ("refusal", .refusal),
        ("model_context_window_exceeded", .contextWindowExceeded), ("something_new", .other("something_new"))
    ])
    func `every stop reason is named`(wire: String, reason: StopReason) throws {
        let events = try decode([
            frame(
                "message_delta",
                #"{"type":"message_delta","delta":{"stop_reason":"\#(wire)"},"usage":{"output_tokens":1}}"#), ""
        ])
        #expect(events == [.messageDelta(stopReason: reason, usage: TokenUsage(output: 1))])
    }

    @Test func `what this decoder does not know is reported, not dropped`() throws {
        let events = try decode([
            frame(
                "content_block_start",
                #"{"type":"content_block_start","index":2,"content_block":{"type":"server_tool_use","id":"s","name":"web_search","input":{}}}"#
            ),
            frame(
                "content_block_delta",
                #"{"type":"content_block_delta","index":2,"delta":{"type":"citations_delta","citation":{}}}"#),
            frame("brand_new_event", #"{"type":"brand_new_event"}"#),
            ""
        ])
        #expect(
            events == [
                .blockStarted(index: 2, .unrecognized(type: "server_tool_use")),
                .unrecognized(event: "content_block_delta", type: "citations_delta"),
                .unrecognized(event: "brand_new_event", type: "brand_new_event")
            ])
    }

    @Test(arguments: [
        ("overloaded_error", ProviderFailure.Kind.overloaded), ("rate_limit_error", .rateLimited),
        ("authentication_error", .authentication), ("permission_error", .permission),
        ("invalid_request_error", .invalidRequest), ("not_found_error", .notFound),
        ("request_too_large", .requestTooLarge), ("api_error", .server), ("novel_error", .other("novel_error"))
    ])
    func `an error event fails the stream with a typed reason`(wire: String, kind: ProviderFailure.Kind) {
        #expect(throws: AnthropicStreamError.provider(ProviderFailure(kind: kind, message: "Overloaded"))) {
            _ = try decode([frame("error", #"{"type":"error","error":{"type":"\#(wire)","message":"Overloaded"}}"#), ""]
            )
        }
    }

    @Test func `a malformed event fails the stream and names the event`() {
        #expect(throws: AnthropicStreamError.malformed(event: "content_block_delta")) {
            _ = try decode([frame("content_block_delta", #"{"type":"content_block_delta","index":"#), ""])
        }
        #expect(throws: AnthropicStreamError.malformed(event: "content_block_delta")) {
            _ = try decode([
                frame(
                    "content_block_delta", #"{"type":"content_block_delta","delta":{"type":"text_delta","text":"x"}}"#),
                ""
            ])
        }
    }
}
