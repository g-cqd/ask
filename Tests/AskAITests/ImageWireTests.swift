import Foundation
import Testing

@testable import AskAI

/// Where an image goes on each wire, and who decides it goes at all (roadmap 0084): one rule before every encoder, and
/// one shape for the two wires that cannot put a picture in a tool result.
@Suite("Images follow the tool result on OpenAI's wires, and only a model known to take them is sent any")
struct ImageWireTests {
    private let image = ImagePart(mediaType: "image/png", data: [1, 2, 3, 4])

    private var messages: [ModelMessage] {
        [
            ModelMessage(
                role: .user, blocks: [.toolResult(id: "t1", content: "a.png: image", isError: false, images: [image])])
        ]
    }

    private func request(_ messages: [ModelMessage]) -> ModelRequest {
        ModelRequest(model: "m", maxTokens: 1, systemPrompt: [], messages: messages, tools: [])
    }

    @Test func `chat completions puts the picture in a user message after the tool message`() {
        let body = String(decoding: OpenAIRequestEncoder.encode(request(messages)), as: UTF8.self)
        #expect(
            body.contains(
                #"{"role":"tool","tool_call_id":"t1","content":"a.png: image\n[the image is attached in the next message]"}"#
            ))
        #expect(
            body.contains(
                #"{"role":"user","content":[{"type":"text","text":"\#(ImagePart.attachedLead)"},"#
                    + #"{"type":"image_url","image_url":{"url":"data:image/png;base64,AQIDBA==","detail":"auto"}}]}"#))
    }

    @Test func `the Responses wire does the same with input_image`() {
        let body = String(decoding: ResponsesRequestEncoder.encode(request(messages)), as: UTF8.self)
        #expect(body.contains(#""type":"function_call_output","call_id":"t1","output":"a.png: image\n[the image"#))
        #expect(body.contains(#"{"type":"input_image","detail":"auto","image_url":"data:image/png;base64,AQIDBA=="}"#))
    }

    @Test func `a result without images is written as before`() {
        let plain = [ModelMessage(role: .user, blocks: [.toolResult(id: "t1", content: "42", isError: false)])]
        let body = String(decoding: OpenAIRequestEncoder.encode(request(plain)), as: UTF8.self)
        #expect(!body.contains("image_url") && body.contains(#""content":"42""#))
    }

    @Test func `images are withheld with a reason unless the model is known to take them`() {
        #expect(ImagePart.filtering(messages, accepts: true) == messages)
        let unknown = ImagePart.filtering(messages, accepts: nil)
        let refused = ImagePart.filtering(messages, accepts: false)
        for filtered in [unknown, refused] {
            guard case .toolResult(_, let content, _, let images) = filtered[0].blocks[0] else {
                Issue.record("not a tool result")
                return
            }
            #expect(images.isEmpty && content.hasPrefix("a.png: image\n[an image read here not sent: "))
        }
        #expect(String(describing: unknown).contains("not known"))
        #expect(String(describing: refused).contains("does not accept"))
    }

    @Test func `the two subscriptions are known to take images, others only when something says so`() {
        #expect(ResolvedModel(provider: .anthropic, model: "m").acceptsImages == true)
        #expect(ResolvedModel(provider: .codex, model: "m").acceptsImages == true)
        #expect(ResolvedModel(provider: .codex, model: "m", acceptsImages: false).acceptsImages == false)
        #expect(ResolvedModel(provider: .copilot, model: "m").acceptsImages == nil)
        #expect(ResolvedModel(provider: .agy, model: "m", acceptsImages: true).acceptsImages == true)
    }

    @Test func `Codex reports image input through its modalities, and a catalogue that is silent leaves it unknown`()
        throws
    {
        func entry(_ modalities: String) throws -> CatalogModel? {
            let json = #"{"slug":"gpt-x",\#(modalities)"visibility":"list","priority":1}"#
            return try JSONDecoder().decode(CodexCatalogEntry.self, from: Data(json.utf8)).model
        }
        #expect(try entry(#""input_modalities":["text","image"],"#)?.acceptsImages == true)
        #expect(try entry(#""input_modalities":["text"],"#)?.acceptsImages == false)
        #expect(try entry("")?.acceptsImages == nil)
    }
}
