import Foundation
import Testing

@testable import AskAI

/// Copilot reports what a model takes of images, and wants a request that holds one to say so (roadmap 0084).
@Suite("Copilot's vision limits are read from its catalogue, and a request with a picture says it has one")
struct CopilotVisionTests {
    private func file(_ root: URL) throws -> CredentialFile {
        let file = CredentialFile(url: root.appending(path: "config/credentials.json"))
        try file.saveCopilot(
            CopilotCredentials(
                githubToken: "GITHUB-SECRET", accessToken: "SHORT-SECRET",
                expiresAt: Date().timeIntervalSince1970 + 3600,
                apiURL: CopilotProtocol.defaultAPI, machineID: "machine", deviceID: "device"))
        return file
    }

    private static func entry(_ id: String, _ vision: String, _ limits: String) -> String {
        """
        {"id":"\(id)","model_picker_enabled":true,"supported_endpoints":["/chat/completions"],\
        "capabilities":{"type":"chat","supports":{"tool_calls":true,"streaming":true\(vision)},\
        "limits":{"max_context_window_tokens":200000,"max_output_tokens":4096\(limits)}}}
        """
    }

    private static let catalog =
        "{\"data\":["
        + [
            entry(
                "sees", ",\"vision\":true",
                ",\"vision\":{\"max_prompt_images\":5,\"max_prompt_image_size\":3145728,"
                    + "\"supported_media_types\":[\"image/jpeg\",\"image/png\",\"application/pdf\"]}"),
            entry("blind", ",\"vision\":false", ""),
            entry("silent", "", "")
        ]
        .joined(separator: ",") + "]}"

    @Test func `the vision flag and block become acceptance and limits, and silence stays unknown`() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let transport = CopilotTestTransport { _ in CopilotTestTransport.reply(Self.catalog) }
        let models = try await CopilotCatalog(file: try file(root), transport: transport)
            .models(now: Date().timeIntervalSince1970)
        let sees = try #require(models.first { $0.id == "sees" })
        #expect(sees.acceptsImages == true)
        #expect(
            sees.imageLimits
                == ImageLimits(
                    maximumImages: 5, maximumBytes: 3_145_728,
                    mediaTypes: ["image/jpeg", "image/png", "application/pdf"]))
        #expect(models.first { $0.id == "blind" }?.acceptsImages == false)
        #expect(models.first { $0.id == "silent" }?.acceptsImages == nil)
    }

    @Test func `only a request holding a picture carries the vision header`() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let sse = try String(
            contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
                .appending(path: "Fixtures/OpenAICompatible/llamacpp-text.sse"),
            encoding: .utf8)
        let transport = CopilotTestTransport {
            CopilotTestTransport.reply($0.url.path == "/models" ? Self.catalog : sse)
        }
        let client = CopilotClient(file: try file(root), transport: transport)
        let picture = ModelMessage(
            role: .user,
            blocks: [
                .toolResult(
                    id: "t", content: "x", isError: false, images: [ImagePart(mediaType: "image/png", data: [1])])
            ])
        let plain = ModelMessage(role: .user, blocks: [.text("hi")])
        for (messages, expected) in [([plain], false), ([plain, picture], true)] {
            let request = ModelRequest(model: "sees", maxTokens: 10, systemPrompt: [], messages: messages, tools: [])
            for try await _ in client.stream(request) {}
            let sent = try #require(transport.requests.last)
            #expect(sent.headers.contains { $0.name == "copilot-vision-request" && $0.value == "true" } == expected)
        }
    }
}
