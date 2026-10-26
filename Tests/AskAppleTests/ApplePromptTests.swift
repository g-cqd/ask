internal import AskAI
internal import Foundation
internal import Testing

@testable import AskApple

/// The conversation as a four-thousand-token model reads it: newest turns whole, oldest dropped first, long results cut in the middle.
@Suite("The on-device prompt keeps the newest turns and cuts what does not fit")
struct ApplePromptTests {
    private func object(_ json: String) throws -> JSONObject { try JSONObject(validating: Array(json.utf8)) }

    @Test func `user and assistant turns are labelled, oldest first`() {
        let turns = ApplePrompt.turns([
            ModelMessage(role: .user, blocks: [.text("hello")]), ModelMessage(role: .assistant, blocks: [.text("hi")])
        ])
        #expect(turns == ["User: hello", "Assistant: hi"])
    }

    @Test func `a tool call and its result are turns that name the tool, whose id is not repeated`() throws {
        let turns = ApplePrompt.turns([
            ModelMessage(
                role: .assistant, blocks: [.toolCall(id: "t1", name: "read", input: try object(#"{"path":"a"}"#))]),
            ModelMessage(role: .user, blocks: [.toolResult(id: "t1", content: "contents", isError: false)])
        ])
        #expect(turns[0] == #"Assistant called read with {"path":"a"}"#)
        #expect(turns[1] == "The read returned:\ncontents")
        #expect(!turns.joined().contains("t1"))
    }

    @Test func `a failed tool says so`() {
        let turns = ApplePrompt.turns([
            ModelMessage(role: .assistant, blocks: [.toolCall(id: "x", name: "bash", input: .empty)]),
            ModelMessage(role: .user, blocks: [.toolResult(id: "x", content: "boom", isError: true)])
        ])
        #expect(turns[1].hasPrefix("The bash failed:"))
    }

    @Test func `another model's reasoning is not replayed`() {
        let turns = ApplePrompt.turns([
            ModelMessage(role: .assistant, blocks: [.thinking(text: "secret chain", signature: "s"), .text("answer")]),
            ModelMessage(role: .assistant, blocks: [.redactedThinking(data: "d")])
        ])
        #expect(turns == ["Assistant: answer"])
    }

    @Test func `a long result is cut in its middle, with the cut marked`() {
        let long = String(repeating: "a", count: 5_000) + "END"
        let turn =
            ApplePrompt.turns([
                ModelMessage(role: .user, blocks: [.toolResult(id: "i", content: long, isError: false)])
            ])[0]
        #expect(turn.count < ApplePrompt.resultLimit + 60 && turn.contains("[…cut…]") && turn.hasSuffix("END"))
    }

    @Test func `the newest turns that fit are kept, whole, in order`() {
        let turns = (1 ... 10).map { "turn \($0) " + String(repeating: "x", count: 90) }
        let kept = ApplePrompt.fit(turns, budget: 300)
        #expect(kept.contains("turn 10") && kept.contains("turn 9") && !kept.contains("turn 1 "))
        #expect(kept.range(of: "turn 9")!.lowerBound < kept.range(of: "turn 10")!.lowerBound)
        #expect(kept.count <= 300)
    }

    @Test func `the newest turn is kept even when it alone is too long, cut to fit`() {
        let kept = ApplePrompt.fit(["old", String(repeating: "n", count: 1_000)], budget: 200)
        #expect(kept.count <= 200 && !kept.contains("old"))
    }

    @Test func `nothing in, nothing out`() { #expect(ApplePrompt.fit([], budget: 100).isEmpty) }

    @Test func `instructions keep ask's own block whole and add the others only while they fit`() {
        let result = ApplePrompt.instructions(
            ["first block", "second", String(repeating: "z", count: 500)], budget: 100)
        #expect(
            result.text == "first block\n\nsecond" && result.omitted == 1,
            "the left-out block is counted, so it can be said")
    }

    @Test func `ask's own block is cut rather than dropped when it alone is over budget`() {
        let result = ApplePrompt.instructions([String(repeating: "q", count: 500)], budget: 100)
        #expect(!result.text.isEmpty && result.text.count <= 100 && result.omitted == 1)
    }

    @Test func `the estimate rounds up and never says zero for something`() {
        #expect(ApplePrompt.estimatedTokens("") == 0 && ApplePrompt.estimatedTokens("a") == 1)
        #expect(ApplePrompt.estimatedTokens(String(repeating: "a", count: 7)) == 3)
    }
}
