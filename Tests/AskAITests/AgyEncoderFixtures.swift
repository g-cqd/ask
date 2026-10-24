internal import AemiJSON
internal import Foundation
internal import Testing

@testable import AskAI

/// The Cloud Code request. The envelope and the `contents` shapes are the ones the live probes sent and the server accepted
/// (ADR-0080); where a field was not probed, the test says so.
/// The helpers the encoder tests share: a request, its encoding, and the turns it produced.
enum AgyEncoderFixtures {
    static let gemini = "gemini-3-flash"

    static func json(_ text: String) throws -> JSONObject { try JSONObject(validating: Array(text.utf8)) }

    static func request(
        _ messages: [ModelMessage], model: String = gemini, system: [String] = [], tools: [ToolDefinition] = [],
        maxTokens: Int = 1000, thinking: ThinkingControl? = nil
    ) -> ModelRequest {
        ModelRequest(
            model: model, maxTokens: maxTokens, systemPrompt: system, messages: messages, tools: tools,
            thinking: thinking)
    }

    static func encode(_ request: ModelRequest) throws -> JSON {
        let bytes = try AgyRequestEncoder.encode(request, project: "proj-1", requestID: "req-1", promptID: "prompt-1")
        return try AemiJSON.parse(bytes).root
    }

    static func contents(_ messages: [ModelMessage], model: String = gemini) throws -> [JSON] {
        try encode(request(messages, model: model))["request"]["contents"].array ?? []
    }

    static func user(_ text: String) -> ModelMessage { ModelMessage(role: .user, blocks: [.text(text)]) }

    static func call(_ id: String, _ name: String = "calc") throws -> RequestBlock {
        .toolCall(id: id, name: name, input: try json(#"{"a":1}"#))
    }

    static func carrier(_ signature: String, model: String = gemini) -> RequestBlock {
        .thinking(
            text: "",
            signature: ReasoningProvenance.mark(scheme: AgyThoughtSignature.scheme(model: model), payload: signature))
    }

    static func calls(in message: JSON) -> [JSON] {
        (message["parts"].array ?? []).filter { $0["functionCall"].isObject }
    }

    // MARK: - Envelope
}
