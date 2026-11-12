import Foundation
import Testing

@testable import AskAI

/// A picture the person pasted, in their own message (roadmap 0224): each wire carries it beside the message's text, and only a
/// model known to take images is sent one; the others are told it was not sent, and why.
@Suite("A pasted picture rides in the person's message on every wire")
struct UserImageWireTests {
    private let image = ImagePart(mediaType: "image/png", data: [1, 2, 3, 4])
    private let data = "data:image/png;base64,AQIDBA=="

    private var messages: [ModelMessage] {
        [ModelMessage(role: .user, blocks: [.text("look at this"), .image(image)])]
    }

    private func request(_ messages: [ModelMessage], model: String = "m") -> ModelRequest {
        ModelRequest(model: model, maxTokens: 1, systemPrompt: [], messages: messages, tools: [])
    }

    @Test func `Anthropic: an image block after the text, in the same message`() {
        let body = String(decoding: AnthropicRequestEncoder.encode(request(messages)), as: UTF8.self)
        #expect(
            body.contains(
                #"{"type":"text","text":"look at this"},{"type":"image","source":{"type":"base64","media_type":"image/png","#
                    + #""data":"AQIDBA=="}"#
            ),
            "\(body)"
        )
    }

    @Test func `chat completions and Responses: one user message with the text and the picture`() {
        let chat = String(decoding: OpenAIRequestEncoder.encode(request(messages)), as: UTF8.self)
        #expect(
            chat.contains(
                #"{"role":"user","content":[{"type":"text","text":"look at this"},"#
                    + #"{"type":"image_url","image_url":{"url":"\#(data)","detail":"auto"}}]}"#
            ),
            "\(chat)"
        )
        let responses = String(decoding: ResponsesRequestEncoder.encode(request(messages)), as: UTF8.self)
        #expect(
            responses.contains(
                #"{"role":"user","content":[{"type":"input_text","text":"look at this"},"#
                    + #"{"type":"input_image","detail":"auto","image_url":"\#(data)"}]}"#
            ),
            "\(responses)"
        )
    }

    @Test func `text alone is written as before on the chat wire`() {
        let plain = [ModelMessage(role: .user, blocks: [.text("hello")])]
        let chat = String(decoding: OpenAIRequestEncoder.encode(request(plain)), as: UTF8.self)
        #expect(chat.contains(#"{"role":"user","content":"hello"}"#))
    }

    @Test func `Antigravity: an inlineData part after the text`() throws {
        let body = String(
            decoding: try AgyRequestEncoder.encode(
                request(messages, model: "gemini-3-flash"),
                project: "p",
                requestID: "r",
                promptID: "q"
            ),
            as: UTF8.self
        )
        #expect(
            body.contains(#"{"text":"look at this"},{"inlineData":{"mimeType":"image/png","data":"AQIDBA=="}}"#),
            "\(body)"
        )
    }

    @Test func `a model not known to take images is told the picture was not sent, and why`() {
        #expect(ImagePart.filtering(messages, accepts: true) == messages)
        #expect(messages[0].holdsImages)
        for accepts in [false, nil] as [Bool?] {
            let filtered = ImagePart.filtering(messages, accepts: accepts)
            #expect(!filtered[0].holdsImages)
            guard case .text(let note) = filtered[0].blocks.last else {
                Issue.record("the picture is not replaced by a line")
                return
            }
            #expect(note.hasPrefix("[an image pasted here not sent: "), "\(note)")
        }
    }

    @Test func `pasted pictures count toward a request's limit, oldest let go first`() {
        let many = (0 ..< 3).map { _ in ModelMessage(role: .user, blocks: [.text("x"), .image(image)]) }
        let kept = ImagePart.filtering(many, accepts: true, limits: ImageLimits(maximumImages: 2))
        #expect(kept.filter(\.holdsImages).count == 1, "down to half of 2")
        #expect(kept.last?.holdsImages == true, "the newest kept")
    }
}
