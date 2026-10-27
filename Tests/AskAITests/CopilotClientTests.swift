import Foundation
import Testing

@testable import AskAI

@Suite("Copilot account catalogs gate all three native inference transports")
struct CopilotClientTests {
    private func file(_ root: URL) throws -> CredentialFile {
        let file = CredentialFile(url: root.appending(path: "config/credentials.json"))
        try file.saveCopilot(
            CopilotCredentials(
                githubToken: "GITHUB-SECRET", accessToken: "SHORT-SECRET",
                expiresAt: Date().timeIntervalSince1970 + 3600,
                apiURL: CopilotProtocol.defaultAPI, machineID: "machine", deviceID: "device"))
        return file
    }
    private static func catalog(_ api: String) -> String {
        """
        {"data":[{"id":"m","model_picker_enabled":true,"supported_endpoints":["\(api)"],"capabilities":{"type":"chat","supports":{"tool_calls":true,"streaming":true},"limits":{"max_context_window_tokens":200000,"max_output_tokens":4096}}}]}
        """
    }
    private func fixture(_ api: String) throws -> String {
        if api == "/v1/messages" {
            return
                "event: message_start\ndata: {\"type\":\"message_start\",\"message\":{\"id\":\"m\",\"model\":\"m\",\"usage\":{\"input_tokens\":1,\"output_tokens\":1}}}\n\nevent: message_stop\ndata: {\"type\":\"message_stop\"}\n\n"
        }
        let folder = api == "/responses" ? "Responses" : "OpenAICompatible"
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Fixtures/\(folder)/llamacpp-text.sse")
        return try String(contentsOf: url, encoding: .utf8)
    }

    @Test(arguments: ["/responses", "/v1/messages", "/chat/completions"])
    func `catalog protocol controls inference and only the short token leaves for it`(api: String) async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = try file(root)
        let sse = try fixture(api)
        let transport = CopilotTestTransport { request in
            CopilotTestTransport.reply(request.url.path == "/models" ? Self.catalog(api) : sse)
        }
        let client = CopilotClient(file: file, transport: transport)
        let request = ModelRequest(
            model: "m", maxTokens: 10, systemPrompt: [], messages: [ModelMessage(role: .user, blocks: [.text("hi")])],
            tools: [])
        var count = 0
        for try await _ in client.stream(request) { count += 1 }
        #expect(count > 0)
        let sent = try #require(transport.requests.last)
        #expect(sent.url.path == api && !sent.allowsRedirects)
        #expect(sent.headers.contains { $0.name == "authorization" && $0.value == "Bearer SHORT-SECRET" })
        #expect(sent.headers.contains { $0.name == "x-initiator" && $0.value == "user" })
        #expect(!sent.headers.contains { $0.value.contains("GITHUB-SECRET") || $0.name == "x-api-key" })
        let cache = try String(contentsOf: root.appending(path: "config/models-copilot-vscode.json"), encoding: .utf8)
        #expect(!cache.contains("SECRET"))
    }

    @Test func `empty successful catalogs replace stale entries and unknown models never infer`() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = try file(root)
        let initial = CopilotTestTransport { _ in CopilotTestTransport.reply(Self.catalog("/responses")) }
        let now = Date().timeIntervalSince1970
        _ = try await CopilotCatalog(file: file, transport: initial).models(now: now)
        let revoked = CopilotTestTransport { _ in CopilotTestTransport.reply(#"{"data":[]}"#) }
        let catalog = CopilotCatalog(file: file, transport: revoked)
        #expect(try await catalog.models(now: now, refresh: true).isEmpty)
        #expect(try catalog.cached(now: now)?.isEmpty == true)
        let request = ModelRequest(model: "m", maxTokens: 10, systemPrompt: [], messages: [], tools: [])
        await #expect(throws: (any Error).self) {
            for try await _ in CopilotClient(file: file, transport: revoked).stream(request) {}
        }
        #expect(revoked.requests.allSatisfy { $0.url.path == "/models" })
    }

    @Test(arguments: ["picker", "tools", "streaming", "protocol", "policy"])
    func `ineligible account models never become choices`(reason: String) async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = try file(root)
        var payload = Self.catalog("/responses")
        switch reason {
            case "picker":
                payload = payload.replacing("\"model_picker_enabled\":true", with: "\"model_picker_enabled\":false")
            case "tools": payload = payload.replacing("\"tool_calls\":true", with: "\"tool_calls\":false")
            case "streaming": payload = payload.replacing("\"streaming\":true", with: "\"streaming\":false")
            case "protocol": payload = payload.replacing("/responses", with: "/websocket")
            default:
                payload = payload.replacing("\"id\":\"m\"", with: "\"id\":\"m\",\"policy\":{\"state\":\"disabled\"}")
        }
        let body = payload
        let transport = CopilotTestTransport { _ in CopilotTestTransport.reply(body) }
        #expect(
            try await CopilotCatalog(file: file, transport: transport).models(now: Date().timeIntervalSince1970).isEmpty
        )
    }

    @Test(arguments: [401, 402, 403, 429, 500])
    func `HTTP errors cannot echo provider secrets`(status: Int) async throws {
        let transport = CopilotTestTransport { _ in CopilotTestTransport.reply("LEAKED-SECRET", status: status) }
        let url = URL(string: "https://api.githubcopilot.com/responses")!
        let guarded = CopilotTransport(inner: transport, url: url)
        let response = try await guarded.send(
            HTTPRequest(url: url, method: "POST", headers: [], body: [], allowsRedirects: false))
        #expect(response.status == status)
        #expect(!String(decoding: try await response.collect(), as: UTF8.self).contains("LEAKED-SECRET"))
    }
}
