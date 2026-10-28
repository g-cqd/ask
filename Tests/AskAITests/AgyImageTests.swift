import Foundation
import Testing

@testable import AskAI

/// A tool result's picture on the Antigravity wire (roadmap 0084): inside the function response for Gemini 3, after it for the rest.
@Suite("Antigravity carries a picture as inlineData, nested for Gemini 3 and beside the results for other models")
struct AgyImageTests {
    private func body(model: String) throws -> String {
        let call = ModelMessage(
            role: .assistant,
            blocks: [.toolCall(id: "c1", name: "read", input: try .init(validating: Array("{}".utf8)))])
        let result = ModelMessage(
            role: .user,
            blocks: [
                .toolResult(
                    id: "c1", content: "a.png: image", isError: false,
                    images: [ImagePart(mediaType: "image/png", data: [1, 2, 3, 4])])
            ])
        let request = ModelRequest(model: model, maxTokens: 1, systemPrompt: [], messages: [call, result], tools: [])
        return String(
            decoding: try AgyRequestEncoder.encode(request, project: "p", requestID: "r", promptID: "q"), as: UTF8.self)
    }

    private let inline = #"{"inlineData":{"mimeType":"image/png","data":"AQIDBA=="}}"#

    @Test func `Gemini 3 nests the picture in the function response`() throws {
        let sent = try body(model: "gemini-3-flash")
        #expect(sent.contains(#""parts":[\#(inline)]"#))
        #expect(!sent.contains("attached in the next message"))
    }

    @Test func `other models get the picture as a part after the results, and the result says so`() throws {
        let sent = try body(model: "claude-sonnet-5-5-low")
        #expect(sent.contains(#"a.png: image\n[the image is attached in the next message]"#))
        #expect(sent.contains(inline))
        #expect(!sent.contains(#""parts":[\#(inline)]"#))
    }

    @Test func `the models Antigravity lists are judged by name`() {
        #expect(AgyImagePlacement.accepts(model: "gemini-3-flash") == true)
        #expect(AgyImagePlacement.accepts(model: "claude-opus-5-5-low") == true)
        #expect(AgyImagePlacement.accepts(model: "gpt-oss-120b-medium") == false)
        #expect(AgyImagePlacement.accepts(model: "something-new") == nil)
        #expect(ResolvedModel(provider: .agy, model: "gemini-3-flash").acceptsImages == true)
    }
}
