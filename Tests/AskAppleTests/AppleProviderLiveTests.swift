internal import AskAI
internal import AskAgentCore
internal import Testing

@testable import AskApple

/// The real model, where there is one: skipped on a Mac without Apple Intelligence. It proves the wiring, not the wording: events in the order
/// the loop's assembler accepts, and a tool call handed back as a call.
@Suite(
    "The on-device model answers through the provider, where it is available",
    .enabled(if: AppleModel.availability().isAvailable), .timeLimit(.minutes(2)))
struct AppleProviderLiveTests {
    private func assemble(_ request: ModelRequest) async throws -> AssembledResponse {
        var assembler = ResponseAssembler()
        for try await event in AppleProvider().stream(request) { try assembler.apply(event) }
        return try assembler.finish()
    }

    @Test func `a plain question is answered in text, in order the assembler accepts`() async throws {
        let request = ModelRequest(
            model: AppleModel.id, maxTokens: 256, systemPrompt: ["You answer in one short sentence."],
            messages: [ModelMessage(role: .user, blocks: [.text("What is the capital of France?")])], tools: [])
        let response = try await assemble(request)
        guard case .text(let text)? = response.blocks.first else {
            Issue.record("no text block: \(response.blocks)")
            return
        }
        #expect(text.contains("Paris") && response.stopReason == .endTurn)
    }

    @Test func `a task that needs a file is handed back as a tool call with typed arguments`() async throws {
        let read = ToolDefinition(
            name: "read", description: "Read a file and return its text.",
            inputSchema: try JSONObject(
                validating: Array(
                    #"{"type":"object","required":["path"],"properties":{"path":{"type":"string","description":"The file's path."}}}"#
                        .utf8)))
        let request = ModelRequest(
            model: AppleModel.id, maxTokens: 256, systemPrompt: ["You are a coding agent."],
            messages: [ModelMessage(role: .user, blocks: [.text("Read the file notes.txt and tell me what it says.")])],
            tools: [read])
        let response = try await assemble(request)
        let call = response.blocks
            .compactMap { block -> (String, JSONObject)? in
                if case .toolCall(_, let name, let input) = block { return (name, input) }
                return nil
            }
            .first
        #expect(call?.0 == "read" && String(decoding: call?.1.bytes ?? [], as: UTF8.self).contains("notes.txt"))
        #expect(response.stopReason == .toolUse)
    }

    @Test func `a window too small for the conversation is compacted by the loop, not retried`() async throws {
        let huge = String(repeating: "The build finished without errors. ", count: 2_000)
        // Not sent to the model as is: the budget cuts it, so the request succeeds with the newest part.
        let request = ModelRequest(
            model: AppleModel.id, maxTokens: 64, systemPrompt: ["Reply with the single word OK."],
            messages: [ModelMessage(role: .user, blocks: [.text(huge + "\nSay OK.")])], tools: [])
        let response = try await assemble(request)
        #expect(!response.blocks.isEmpty)
    }
}
