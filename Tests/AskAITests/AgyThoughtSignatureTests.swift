internal import AemiJSON
internal import Foundation
internal import Testing

@testable import AskAI

/// The Cloud Code request. The envelope and the `contents` shapes are the ones the live probes sent and the server accepted
/// (ADR-0080); where a field was not probed, the test says so.
/// The thought signature of a replayed call, and the model-version rule (ADR-0090).
struct AgyThoughtSignatureTests {
    // MARK: - Thought signatures

    private func firstTurn(_ blocks: [RequestBlock], model: String = "gemini-3-flash") throws -> [JSON] {
        AgyEncoderFixtures.calls(
            in: try AgyEncoderFixtures.contents([ModelMessage(role: .assistant, blocks: blocks)], model: model)[0])
    }

    @Test func `a signature the same model issued goes back on the very part of its call`() throws {
        let calls = try firstTurn([AgyEncoderFixtures.carrier("REAL"), try AgyEncoderFixtures.call("c1")])
        #expect(calls.count == 1 && calls[0]["thoughtSignature"].string == "REAL")
    }

    @Test func `a first call with no signature gets the sentinel, a later one gets nothing`() throws {
        let calls = try firstTurn([try AgyEncoderFixtures.call("c1"), try AgyEncoderFixtures.call("c2")])
        #expect(calls.map { $0["thoughtSignature"].string } == [AgyThoughtSignature.sentinel, nil])
    }

    @Test func `the sentinel is never put over a real signature, and a later real one is kept`() throws {
        let real = try firstTurn([
            AgyEncoderFixtures.carrier("A"), try AgyEncoderFixtures.call("c1"), try AgyEncoderFixtures.call("c2")
        ])
        #expect(real.map { $0["thoughtSignature"].string } == ["A", nil])
        let late = try firstTurn([
            try AgyEncoderFixtures.call("c1"), AgyEncoderFixtures.carrier("B"), try AgyEncoderFixtures.call("c2")
        ])
        #expect(late.map { $0["thoughtSignature"].string } == [AgyThoughtSignature.sentinel, "B"])
    }

    @Test func `a signature another model issued is not sent, and the first call gets the sentinel instead`() throws {
        let calls = try firstTurn([
            AgyEncoderFixtures.carrier("OTHER", model: "gemini-3.5-flash-lite"), try AgyEncoderFixtures.call("c1")
        ])
        #expect(calls.map { $0["thoughtSignature"].string } == [AgyThoughtSignature.sentinel])
        let bare = try firstTurn([
            .thinking(text: "", signature: ReasoningProvenance.mark(scheme: "gemini/", payload: "NONAME")),
            try AgyEncoderFixtures.call("c1")
        ])
        #expect(bare.map { $0["thoughtSignature"].string } == [AgyThoughtSignature.sentinel])
    }

    @Test func `each model turn is its own, and a turn with no call has no signature at all`() throws {
        let messages = [
            ModelMessage(role: .assistant, blocks: [try AgyEncoderFixtures.call("c1")]),
            ModelMessage(role: .user, blocks: [.toolResult(id: "c1", content: "r", isError: false)]),
            ModelMessage(role: .assistant, blocks: [.text("answer")]), AgyEncoderFixtures.user("next"),
            ModelMessage(role: .assistant, blocks: [AgyEncoderFixtures.carrier("K"), try AgyEncoderFixtures.call("c2")])
        ]
        let contents = try AgyEncoderFixtures.contents(messages)
        #expect(
            AgyEncoderFixtures.calls(in: contents[0]).first?["thoughtSignature"].string == AgyThoughtSignature.sentinel)
        #expect(!String(decoding: try contents[2].encodedBytes(), as: UTF8.self).contains("thoughtSignature"))
        #expect(AgyEncoderFixtures.calls(in: contents[4]).first?["thoughtSignature"].string == "K")
    }

    @Test func `a signature that is not followed by a call is dropped`() throws {
        let contents = try AgyEncoderFixtures.contents([
            ModelMessage(
                role: .assistant,
                blocks: [AgyEncoderFixtures.carrier("LOST"), .text("then text"), try AgyEncoderFixtures.call("c1")])
        ])
        let text = String(decoding: try contents[0].encodedBytes(), as: UTF8.self)
        #expect(!text.contains("LOST"))
        #expect(
            AgyEncoderFixtures.calls(in: contents[0]).first?["thoughtSignature"].string == AgyThoughtSignature.sentinel)
    }

    @Test func `models that do not take a signature never get one, not even a matching one`() throws {
        for model in ["claude-sonnet-5-5-low", "gpt-oss-120b-medium", "gemini-2.4-flash", "gemini-2-flash"] {
            let blocks = [
                AgyEncoderFixtures.carrier("REAL", model: model), try AgyEncoderFixtures.call("c1"),
                try AgyEncoderFixtures.call("c2")
            ]
            let text = String(
                decoding:
                    try AgyEncoderFixtures.contents([ModelMessage(role: .assistant, blocks: blocks)], model: model)[0]
                    .encodedBytes(), as: UTF8.self)
            #expect(
                !text.contains("thoughtSignature") && !text.contains("REAL") && !text.contains("skip_thought"),
                "\(model)")
        }
    }

    @Test func `the model's version decides: 2.5 and later, as the live refusals show`() {
        // @dl:accept -- a list of model ids is data
        let yes = [
            "gemini-3-flash", "gemini-3.8-flash-tiered", "gemini-3.5-flash-lite", "gemini-3.1-flash-lite", "gemini-3",
            "Gemini-3-Pro", "gemini-live-3-flash", "gemini-10-x", "gemini-03-x", "gemini-2.5-flash",
            "gemini-2.5-flash-lite", "gemini-2.5-flash-thinking",
            "gemini-2.5-pro", "gemini-2.6-x"
        ]
        // @dl:accept -- a list of model ids is data
        let no = [
            "gemini-2.4-flash", "gemini-2-flash", "gemini-2.", "gemini-2.x", "gemini-", "gemini-x-3", "xgemini-3",
            "gemini-live-2",
            "claude-sonnet-5-5-low", "gpt-oss-120b-medium", "", "gemini-live-", "gemini3-flash", "3-flash", "42",
            "live-3-flash", "claude-3-opus", "gpt-oss-4"
        ]
        for model in yes { #expect(AgyThoughtSignature.requiresSignature(model: model), "\(model)") }
        for model in no { #expect(!AgyThoughtSignature.requiresSignature(model: model), "\(model)") }
    }
}
