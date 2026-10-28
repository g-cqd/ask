import Testing

@testable import AskAI

/// A tool result that carries an image (roadmap 0084): Anthropic gets it inside the result; a wire with no image
/// encoding yet says plainly that it was not sent.
@Suite("Images in a tool result reach Anthropic, and are declared missing elsewhere")
struct ImageResultRequestTests {
    private let image = ImagePart(mediaType: "image/png", data: [1, 2, 3, 4])

    private func message() -> ModelMessage {
        ModelMessage(
            role: .user, blocks: [.toolResult(id: "t1", content: "a.png: image", isError: false, images: [image])])
    }

    @Test func `Anthropic carries the image inside the tool result, after its text`() {
        let request = ModelRequest(
            model: "claude-x", maxTokens: 1, systemPrompt: [], messages: [message()], tools: [])
        let body = String(decoding: AnthropicRequestEncoder.encode(request, caching: false), as: UTF8.self)
        #expect(
            body.contains(
                #"{"type":"tool_result","tool_use_id":"t1","content":[{"type":"text","text":"a.png: image"},"#
                    + #"{"type":"image","source":{"type":"base64","media_type":"image/png","data":"AQIDBA=="}}]}"#))
    }

    @Test func `a result with no image keeps the plain string content`() {
        let plain = ModelMessage(role: .user, blocks: [.toolResult(id: "t1", content: "42", isError: false)])
        let request = ModelRequest(model: "claude-x", maxTokens: 1, systemPrompt: [], messages: [plain], tools: [])
        let body = String(decoding: AnthropicRequestEncoder.encode(request, caching: false), as: UTF8.self)
        #expect(body.contains(#""content":"42""#))
    }

    @Test func `a wire without image support says the image was not sent`() {
        #expect(ImagePart.noting([], in: "text") == "text")
        #expect(ImagePart.noting([image], in: "text").contains("could not be sent"))
        #expect(ImagePart.noting([image, image], in: "text").contains("2 images"))
    }
}
