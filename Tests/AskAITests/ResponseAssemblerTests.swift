import Testing

@testable import AskAI

/// Model events fold into one complete response: ordered blocks, validated tool input, merged usage.
@Suite("Responses assemble from model events, and broken streams are named")
struct ResponseAssemblerTests {
    private func assemble(_ events: [ModelEvent]) throws(ResponseAssemblyError) -> AssembledResponse {
        var assembler = ResponseAssembler()
        for event in events { try assembler.apply(event) }
        return try assembler.finish()
    }

    private let start = ModelEvent.messageStarted(
        id: "msg_1", model: "claude-x", usage: TokenUsage(input: 25, output: 1, cacheRead: 7))

    @Test func `a complete turn assembles its blocks in index order`() throws {
        let response = try assemble([
            start,
            .blockStarted(index: 0, .thinking), .thinkingDelta(index: 0, "Let me "), .thinkingDelta(index: 0, "look."),
            .signatureDelta(index: 0, "sig"), .blockStopped(index: 0),
            .blockStarted(index: 1, .text), .textDelta(index: 1, "Reading "), .textDelta(index: 1, "it."),
            .blockStopped(index: 1),
            .blockStarted(index: 2, .toolUse(id: "toolu_1", name: "read")),
            .toolInputDelta(index: 2, #"{"path":"#), .toolInputDelta(index: 2, #" "a.swift"}"#),
            .blockStopped(index: 2),
            .messageDelta(stopReason: .toolUse, usage: TokenUsage(output: 40)), .messageStopped
        ])
        #expect(response.id == "msg_1")
        #expect(response.model == "claude-x")
        #expect(
            response.blocks == [
                .thinking(text: "Let me look.", signature: "sig"),
                .text("Reading it."),
                .toolCall(id: "toolu_1", name: "read", input: Array(#"{"path": "a.swift"}"#.utf8))
            ])
        #expect(response.stopReason == .toolUse)
        // Input and cache counts come from the start; output is the cumulative count from the delta.
        #expect(response.usage == TokenUsage(input: 25, output: 40, cacheRead: 7))
    }

    @Test func `blocks are ordered by index, not by arrival`() throws {
        var events = [start]
        for index in (0 ..< 10).reversed() {
            events += [
                .blockStarted(index: index, .text), .textDelta(index: index, "\(index)"), .blockStopped(index: index)
            ]
        }
        let response = try assemble(events + [.messageStopped])
        #expect(response.blocks == (0 ..< 10).map { .text("\($0)") })
    }

    @Test func `a tool call without input has an empty object`() throws {
        let response = try assemble([
            start, .blockStarted(index: 0, .toolUse(id: "t", name: "now")), .toolInputDelta(index: 0, ""),
            .blockStopped(index: 0), .messageDelta(stopReason: .toolUse, usage: TokenUsage()), .messageStopped
        ])
        #expect(response.blocks == [.toolCall(id: "t", name: "now", input: Array("{}".utf8))])
    }

    @Test func `tool input that is not a JSON object is refused`() {
        for input in [#"{"path": "a"#, "[1]", "42"] {
            #expect(throws: ResponseAssemblyError.invalidToolInput(id: "t")) {
                _ = try assemble([
                    start, .blockStarted(index: 0, .toolUse(id: "t", name: "read")), .toolInputDelta(index: 0, input),
                    .blockStopped(index: 0)
                ])
            }
        }
    }

    @Test func `redacted and unrecognized blocks are kept`() throws {
        let response = try assemble([
            start, .blockStarted(index: 0, .redactedThinking(data: "opaque")), .blockStopped(index: 0),
            .blockStarted(index: 1, .unrecognized(type: "server_tool_use")), .blockStopped(index: 1),
            .unrecognized(event: "content_block_delta", type: "citations_delta"), .messageStopped
        ])
        #expect(response.blocks == [.redactedThinking(data: "opaque"), .unrecognized(type: "server_tool_use")])
        #expect(response.unrecognized == ["content_block_delta/citations_delta"])
    }

    @Test func `a stream that ends early is incomplete, and says where`() {
        #expect(throws: ResponseAssemblyError.incomplete(openBlocks: [1])) {
            _ = try assemble([start, .blockStarted(index: 1, .text), .textDelta(index: 1, "cut")])
        }
        #expect(throws: ResponseAssemblyError.incomplete(openBlocks: [])) {
            _ = try assemble([start, .blockStarted(index: 0, .text), .blockStopped(index: 0)])
        }
    }

    @Test func `events out of order are refused`() {
        let cases: [([ModelEvent], ResponseAssemblyError)] = [
            ([.textDelta(index: 0, "x")], .notStarted),
            ([start, start], .startedTwice),
            ([start, .textDelta(index: 3, "x")], .unknownBlock(index: 3)),
            ([start, .blockStopped(index: 0)], .unknownBlock(index: 0)),
            ([start, .blockStarted(index: 0, .text), .blockStarted(index: 0, .text)], .blockStartedTwice(index: 0)),
            ([start, .blockStarted(index: 0, .text), .toolInputDelta(index: 0, "{}")], .mismatchedDelta(index: 0)),
            (
                [start, .blockStarted(index: 0, .toolUse(id: "t", name: "n")), .textDelta(index: 0, "x")],
                .mismatchedDelta(index: 0)
            ),
            (
                [start, .blockStarted(index: 0, .text), .blockStopped(index: 0), .textDelta(index: 0, "late")],
                .mismatchedDelta(index: 0)
            ),
            ([start, .messageStopped, .messageStopped], .eventAfterStop)
        ]
        for (events, error) in cases {
            #expect(throws: error, "\(events)") {
                var assembler = ResponseAssembler()
                for event in events { try assembler.apply(event) }
            }
        }
    }
}
