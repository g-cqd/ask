import AskAI
import Testing

@testable import AskAgentCore

/// The active branch becomes model messages that are always a valid request, with every repair named.
@Suite("Context becomes valid model messages, and every repair is reported")
struct RequestContextTests {
    private func input(_ json: String) -> JSONObject { try! JSONObject(validating: Array(json.utf8)) }

    private func response(_ blocks: [ContentBlock]) -> SessionPayload {
        .response(
            AssembledResponse(
                id: "m", model: "c", blocks: blocks, stopReason: .toolUse, usage: TokenUsage(), unrecognized: []))
    }

    private func entries(_ payloads: [SessionPayload]) throws -> [SessionEntry] {
        var tree = SessionTree()
        for payload in payloads { try tree.append(payload) }
        return tree.context()
    }

    @Test func `text turns alternate as user and assistant messages`() throws {
        let context = RequestContext(try entries([.user("Hi"), .assistant("Hello"), .user("Bye")]))
        #expect(
            context.messages == [
                ModelMessage(role: .user, blocks: [.text("Hi")]),
                ModelMessage(role: .assistant, blocks: [.text("Hello")]),
                ModelMessage(role: .user, blocks: [.text("Bye")])
            ])
        #expect(context.repairs.isEmpty)
    }

    @Test func `tool results share one user message and lead it`() throws {
        let context = RequestContext(
            try entries([
                .user("Read both"),
                response([
                    .thinking(text: "t", signature: "s"), .toolCall(id: "a", name: "read", input: input("{}")),
                    .toolCall(id: "b", name: "read", input: input("{}"))
                ]),
                .toolResult(callID: "a", content: "A", isError: false),
                .toolResult(callID: "b", content: "B", isError: true),
                .user("Now explain")
            ]))
        #expect(
            context.messages == [
                ModelMessage(role: .user, blocks: [.text("Read both")]),
                ModelMessage(
                    role: .assistant,
                    blocks: [
                        .thinking(text: "t", signature: "s"), .toolCall(id: "a", name: "read", input: input("{}")),
                        .toolCall(id: "b", name: "read", input: input("{}"))
                    ]),
                ModelMessage(
                    role: .user,
                    blocks: [
                        .toolResult(id: "a", content: "A", isError: false),
                        .toolResult(id: "b", content: "B", isError: true),
                        .text("Now explain")
                    ])
            ])
        #expect(context.repairs.isEmpty)
    }

    @Test func `a call without a recorded result gets an interrupted error result`() throws {
        let midBatch = RequestContext(
            try entries([
                .user("go"),
                response([
                    .toolCall(id: "a", name: "read", input: input("{}")),
                    .toolCall(id: "b", name: "bash", input: input("{}"))
                ]),
                .toolResult(callID: "a", content: "A", isError: false)
            ]))
        #expect(
            midBatch.messages.last
                == ModelMessage(
                    role: .user,
                    blocks: [
                        .toolResult(id: "a", content: "A", isError: false),
                        .toolResult(id: "b", content: RequestContext.interruptedResult, isError: true)
                    ]))
        #expect(midBatch.repairs == [.interruptedToolCall(id: "b")])

        let atEnd = RequestContext(
            try entries([.user("go"), response([.toolCall(id: "a", name: "read", input: input("{}"))])]))
        #expect(
            atEnd.messages.last
                == ModelMessage(
                    role: .user,
                    blocks: [
                        .toolResult(id: "a", content: RequestContext.interruptedResult, isError: true)
                    ]))

        let beforeText = RequestContext(
            try entries([
                .user("go"), response([.toolCall(id: "a", name: "read", input: input("{}"))]), .user("stop that")
            ]))
        #expect(
            beforeText.messages.last
                == ModelMessage(
                    role: .user,
                    blocks: [
                        .toolResult(id: "a", content: RequestContext.interruptedResult, isError: true),
                        .text("stop that")
                    ]))
    }

    @Test func `a result whose call is not in context is dropped`() throws {
        let context = RequestContext(
            try entries([
                .user("go"), .toolResult(callID: "gone", content: "x", isError: false), .assistant("ok")
            ]))
        #expect(
            context.messages == [
                ModelMessage(role: .user, blocks: [.text("go")]), ModelMessage(role: .assistant, blocks: [.text("ok")])
            ])
        #expect(context.repairs == [.orphanedToolResult(id: "gone")])
    }

    @Test func `blocks that cannot be replayed are dropped, and an empty response leaves no message`() throws {
        let context = RequestContext(
            try entries([
                .user("a"), response([.unrecognized(type: "server_tool_use")]), .user("b"),
                response([.text("kept"), .unrecognized(type: "x")])
            ]))
        #expect(
            context.messages == [
                ModelMessage(role: .user, blocks: [.text("a"), .text("b")]),
                ModelMessage(role: .assistant, blocks: [.text("kept")])
            ])
        #expect(context.repairs == [.droppedBlock(type: "server_tool_use"), .droppedBlock(type: "x")])
    }

    @Test func `a compaction opens the context as a summary`() throws {
        var tree = SessionTree()
        let first = try tree.append(.user("old"))
        try tree.append(.assistant("old reply"))
        let kept = try tree.append(.user("recent"))
        try tree.append(.compaction(summary: "We discussed X.", firstKept: kept))
        _ = first
        let context = RequestContext(tree.context())
        #expect(
            context.messages == [
                ModelMessage(
                    role: .user, blocks: [.text(RequestContext.summaryPrefix + "We discussed X."), .text("recent")])
            ])
    }
}
