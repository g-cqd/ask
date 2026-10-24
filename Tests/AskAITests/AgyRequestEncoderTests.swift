internal import AemiJSON
internal import Foundation
internal import Testing

@testable import AskAI

/// The Cloud Code request. The envelope and the `contents` shapes are the ones the live probes sent and the server accepted
/// (ADR-0080); where a field was not probed, the test says so.
/// The Cloud Code request. The envelope and the `contents` shapes are the ones the live probes sent and the server accepted
/// (ADR-0080); where a field was not probed, the test says so. Signatures are in `AgyThoughtSignatureTests`.
struct AgyRequestEncoderTests {
    @Test func `the envelope carries the project, the ids, the model and ask's own identity`() throws {
        let root = try AgyEncoderFixtures.encode(AgyEncoderFixtures.request([AgyEncoderFixtures.user("hi")]))
        #expect(root["project"].string == "proj-1" && root["requestId"].string == "req-1")
        #expect(root["model"].string == "gemini-3-flash" && root["userPromptId"].string == "prompt-1")
        #expect(root["userAgent"].string == "ask/0 (Antigravity subscription connector)")
        #expect(root["requestType"].string == "agent")
    }

    @Test func `ids with quotes and control characters stay inside their strings`() throws {
        let bytes = try AgyRequestEncoder.encode(
            AgyEncoderFixtures.request([AgyEncoderFixtures.user("x")]), project: "p\",\"x\":\"y", requestID: "r\n\u{1}",
            promptID: "a\\b")
        let root = try AemiJSON.parse(bytes).root
        #expect(
            root["project"].string == "p\",\"x\":\"y" && root["requestId"].string == "r\n\u{1}"
                && root["x"].string == nil)
        #expect(root["userPromptId"].string == "a\\b")
    }

    @Test func `the output limit is the request's, and thoughts are asked for`() throws {
        let root = try AgyEncoderFixtures.encode(
            AgyEncoderFixtures.request([AgyEncoderFixtures.user("hi")], maxTokens: 777))
        #expect(root["request"]["generationConfig"]["maxOutputTokens"].int == 777)
        #expect(root["request"]["generationConfig"]["thinkingConfig"]["includeThoughts"].bool == true)
    }

    @Test func `an explicit thinking control is refused, not silently dropped`() {
        for control in [ThinkingControl.disabled, .betweenTools, .effort(.high)] {
            #expect(throws: ThinkingError.unsupportedProtocol("Antigravity")) {
                try AgyEncoderFixtures.encode(
                    AgyEncoderFixtures.request([AgyEncoderFixtures.user("hi")], thinking: control))
            }
        }
    }

    @Test func `instructions travel as one system instruction, or not at all`() throws {
        let some = try AgyEncoderFixtures.encode(
            AgyEncoderFixtures.request([AgyEncoderFixtures.user("hi")], system: ["one", "two"]))
        #expect(some["request"]["systemInstruction"]["parts"].array?.first?["text"].string == "one\n\ntwo")
        let none = try AgyEncoderFixtures.encode(AgyEncoderFixtures.request([AgyEncoderFixtures.user("hi")]))
        #expect(!none["request"]["systemInstruction"].exists)
    }

    // MARK: - Tools

    @Test func `tools are one group of declarations with their schemas spliced in, and the mode is automatic`() throws {
        let tools = [
            ToolDefinition(
                name: "calc", description: "Multiply.",
                inputSchema: try AgyEncoderFixtures.json(#"{"type":"object","properties":{"a":{"type":"integer"}}}"#)),
            ToolDefinition(name: "other", description: "d", inputSchema: .empty)
        ]
        let root = try AgyEncoderFixtures.encode(
            AgyEncoderFixtures.request([AgyEncoderFixtures.user("hi")], tools: tools))
        let groups = root["request"]["tools"].array ?? []
        #expect(groups.count == 1)
        let declarations = groups.first?["functionDeclarations"].array ?? []
        #expect(declarations.map { $0["name"].string } == ["calc", "other"])
        #expect(declarations.first?["description"].string == "Multiply.")
        #expect(declarations.first?["parametersJsonSchema"]["properties"]["a"]["type"].string == "integer")
        #expect(root["request"]["toolConfig"]["functionCallingConfig"]["mode"].string == "AUTO")
    }

    @Test func `with no tools there is neither a tool list nor a mode`() throws {
        let root = try AgyEncoderFixtures.encode(AgyEncoderFixtures.request([AgyEncoderFixtures.user("hi")]))
        #expect(!root["request"]["tools"].exists && !root["request"]["toolConfig"].exists)
    }

    // MARK: - Messages

    @Test func `a user turn and an assistant turn keep their order, roles and parts`() throws {
        let messages = [
            AgyEncoderFixtures.user("one"),
            ModelMessage(role: .assistant, blocks: [.text("two"), try AgyEncoderFixtures.call("c1"), .text("three")]),
            AgyEncoderFixtures.user("four")
        ]
        let contents = try AgyEncoderFixtures.contents(messages)
        #expect(contents.map { $0["role"].string } == ["user", "model", "user"])
        let model = contents[1]["parts"].array ?? []
        #expect(model.count == 3 && model[0]["text"].string == "two" && model[2]["text"].string == "three")
        #expect(model[1]["functionCall"]["id"].string == "c1" && model[1]["functionCall"]["name"].string == "calc")
        #expect(model[1]["functionCall"]["args"]["a"].int == 1)
        #expect(contents[0]["parts"].array?.first?["text"].string == "one")
    }

    @Test func `a result goes back under the call's id and name, with its text or its error`() throws {
        let messages = [
            ModelMessage(
                role: .assistant,
                blocks: [try AgyEncoderFixtures.call("c1", "calc"), try AgyEncoderFixtures.call("c2", "read")]),
            ModelMessage(
                role: .user,
                blocks: [
                    .toolResult(id: "c2", content: "boom", isError: true),
                    .toolResult(id: "c1", content: "901", isError: false)
                ])
        ]
        let results = try AgyEncoderFixtures.contents(messages)[1]["parts"].array ?? []
        #expect(results.count == 2)
        #expect(
            results[0]["functionResponse"]["id"].string == "c2"
                && results[0]["functionResponse"]["name"].string == "read")
        #expect(results[0]["functionResponse"]["response"]["error"].string == "boom")
        #expect(!results[0]["functionResponse"]["response"]["output"].exists)
        #expect(
            results[1]["functionResponse"]["id"].string == "c1"
                && results[1]["functionResponse"]["name"].string == "calc")
        #expect(results[1]["functionResponse"]["response"]["output"].string == "901")
    }

    @Test func `results come before the text of the same turn, and a result with no known call keeps a name`() throws {
        let message = ModelMessage(
            role: .user, blocks: [.text("after"), .toolResult(id: "ghost", content: "r", isError: false)])
        let parts = try AgyEncoderFixtures.contents([message])[0]["parts"].array ?? []
        #expect(parts.count == 2)
        #expect(parts[0]["functionResponse"]["id"].string == "ghost")
        #expect(parts[0]["functionResponse"]["name"].string == "unknown_tool")
        #expect(parts[1]["text"].string == "after")
    }

    @Test func `a turn that encodes to nothing is left out`() throws {
        let empty = ModelMessage(
            role: .assistant,
            blocks: [.thinking(text: "t", signature: "plain"), .redactedThinking(data: "d"), .text("")])
        let contents = try AgyEncoderFixtures.contents([
            AgyEncoderFixtures.user("a"), empty, AgyEncoderFixtures.user("b")
        ])
        #expect(contents.map { $0["role"].string } == ["user", "user"])
        #expect(try AgyEncoderFixtures.contents([ModelMessage(role: .user, blocks: [])]).isEmpty)
        #expect(
            try AgyEncoderFixtures.contents([ModelMessage(role: .user, blocks: [.text("")])]).isEmpty,
            "an empty user text is not a part")
    }

    @Test func `reasoning that is not this protocol's never reaches the wire, for any model`() throws {
        let blocks: [RequestBlock] = [
            .thinking(text: "private thoughts", signature: ""),
            .thinking(text: "x", signature: "an-anthropic-signature"),
            .thinking(text: "", signature: ReasoningProvenance.mark(scheme: "responses", payload: "{\"id\":\"rs\"}")),
            .redactedThinking(data: "secret"), .text("visible")
        ]
        for model in [AgyEncoderFixtures.gemini, "claude-sonnet-5-5-low", "gpt-oss-120b-medium", "gemini-2.5-pro"] {
            let text = String(
                decoding: try AgyRequestEncoder.encode(
                    AgyEncoderFixtures.request([ModelMessage(role: .assistant, blocks: blocks)], model: model),
                    project: "p",
                    requestID: "r", promptID: "q"), as: UTF8.self)
            #expect(
                text.contains("visible") && !text.contains("private thoughts")
                    && !text.contains("an-anthropic-signature"), "\(model)")
            #expect(!text.contains("secret") && !text.contains("rs"), "\(model)")
        }
    }
}
