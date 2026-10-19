internal import Foundation
internal import Testing

@testable import AskAI

/// Stream shapes the recordings did not happen to contain, each one a server or a failure seen in the wild.
@Suite("The OpenAI-compatible stream decoder handles the shapes servers send")
struct OpenAIStreamDecoderTests {
    /// Decodes and assembles `chunks`, each one SSE `data:` payload.
    private func assemble(_ chunks: [String]) throws -> AssembledResponse {
        var decoder = OpenAIStreamDecoder()
        var events: [ModelEvent] = []
        for chunk in chunks { try decoder.decode(SSEEvent(name: "message", data: Array(chunk.utf8)), into: &events) }
        try decoder.finish(into: &events)
        var assembler = ResponseAssembler()
        for event in events { try assembler.apply(event) }
        return try assembler.finish()
    }

    private func chunk(_ delta: String, finish: String? = nil) -> String {
        let reason = finish.map { "\"\($0)\"" } ?? "null"
        return #"{"id":"r1","model":"m","choices":[{"index":0,"delta":\#(delta),"finish_reason":\#(reason)}]}"#
    }

    private func calls(_ response: AssembledResponse) -> [String] {
        response.blocks.compactMap {
            guard case .toolCall(_, let name, let input) = $0 else { return nil }
            return name + String(decoding: input.bytes, as: UTF8.self)
        }
    }

    @Test func `two tool calls whose fragments interleave are kept apart by their index`() throws {
        let response = try assemble([
            chunk(
                #"{"tool_calls":[{"index":0,"id":"a","type":"function","function":{"name":"read","arguments":"{\"pa"}}]}"#
            ),
            chunk(
                #"{"tool_calls":[{"index":1,"id":"b","type":"function","function":{"name":"bash","arguments":"{\"com"}}]}"#
            ),
            chunk(#"{"tool_calls":[{"index":0,"function":{"arguments":"th\":\"x\"}"}}]}"#),
            chunk(#"{"tool_calls":[{"index":1,"function":{"arguments":"mand\":\"ls\"}"}}]}"#),
            chunk("{}", finish: "tool_calls"), "[DONE]"
        ])
        #expect(calls(response) == [#"read{"path":"x"}"#, #"bash{"command":"ls"}"#])
    }

    @Test func `a tool call without an id gets a unique one`() throws {
        let response = try assemble([
            chunk(#"{"tool_calls":[{"index":0,"function":{"name":"read","arguments":"{}"}}]}"#),
            chunk(#"{"tool_calls":[{"index":1,"function":{"name":"read","arguments":"{}"}}]}"#),
            chunk("{}", finish: "tool_calls")
        ])
        let ids = response.blocks.compactMap { if case .toolCall(let id, _, _) = $0 { id } else { nil } }
        #expect(ids.count == 2)
        #expect(Set(ids).count == 2)
        #expect(ids.allSatisfy { !$0.isEmpty })
    }

    @Test func `whitespace before real text is kept, and whitespace alone is dropped`() throws {
        let kept = try assemble([chunk(#"{"content":"\n"}"#), chunk(#"{"content":"hi"}"#), chunk("{}", finish: "stop")])
        #expect(kept.blocks == [.text("\nhi")])
        let dropped = try assemble([
            chunk(#"{"content":"\n\n"}"#), chunk(#"{"content":""}"#), chunk("{}", finish: "stop")
        ])
        #expect(dropped.blocks.isEmpty)
    }

    @Test func `reasoning then text then a call become three blocks in order`() throws {
        let response = try assemble([
            chunk(#"{"reasoning_content":"think"}"#), chunk(#"{"reasoning":" more"}"#),
            chunk(#"{"content":"Reading."}"#),
            chunk(#"{"tool_calls":[{"index":0,"id":"c","function":{"name":"read","arguments":"{}"}}]}"#),
            chunk("{}", finish: "tool_calls")
        ])
        #expect(response.blocks.count == 3)
        #expect(response.blocks.first == .thinking(text: "think more", signature: ""))
        #expect(response.blocks.dropFirst().first == .text("Reading."))
    }

    @Test(arguments: [
        ("stop", StopReason.endTurn), ("tool_calls", .toolUse), ("length", .maxTokens),
        ("content_filter", .refusal), ("novel", .other("novel"))
    ])
    func `finish reasons map to the neutral stop reasons`(wire: String, reason: StopReason) throws {
        let response = try assemble([chunk(#"{"content":"x"}"#), chunk("{}", finish: wire)])
        #expect(response.stopReason == reason)
    }

    @Test func `usage in a chunk with no choices is applied, with cached tokens kept apart`() throws {
        let response = try assemble([
            chunk(#"{"content":"x"}"#), chunk("{}", finish: "stop"),
            #"{"id":"r1","model":"m","choices":[],"usage":{"prompt_tokens":100,"completion_tokens":7,"prompt_tokens_details":{"cached_tokens":60}}}"#
        ])
        #expect(response.usage == TokenUsage(input: 40, output: 7, cacheRead: 60))
    }

    @Test func `an error object in the stream fails it with the provider's reason`() {
        let error = #"{"error":{"message":"model overloaded","type":"server_error","code":503}}"#
        #expect(throws: OpenAIStreamError.provider(ProviderFailure(kind: .server, message: "model overloaded"))) {
            _ = try assemble([chunk(#"{"content":"x"}"#), error])
        }
    }

    @Test func `data that is not JSON is refused`() {
        #expect(throws: OpenAIStreamError.malformed) { _ = try assemble(["{not json"]) }
    }

    @Test func `a stream that never says why it stopped is incomplete, not a finished turn`() {
        #expect(throws: OpenAIStreamError.unfinished) { _ = try assemble([chunk(#"{"content":"x"}"#)]) }
    }

    @Test func `a stream with no chunk at all is incomplete`() {
        #expect(throws: OpenAIStreamError.unfinished) { _ = try assemble([]) }
    }

    @Test func `a final message object is not read as more content`() throws {
        // MLX ends with a `chat.completion` object carrying the whole message; reading it would duplicate the text.
        let final =
            #"{"id":"r1","object":"chat.completion","model":"m","choices":[{"index":0,"message":{"content":"hello"},"finish_reason":null}],"usage":{"prompt_tokens":3,"completion_tokens":1}}"#
        let response = try assemble([chunk(#"{"content":"hello"}"#), chunk("{}", finish: "stop"), final])
        #expect(response.blocks == [.text("hello")])
    }
}
