internal import Foundation
internal import Testing

@testable import AskAI

/// The observed Codex catalog, with its large instruction fields deliberately omitted from the fixture.
struct CodexCatalogClientTests {
    private static let credentials = CodexCredentials(
        accessToken: "access-test", refreshToken: "refresh-test", expiresAt: 100, accountID: "account-test")

    private func read(_ json: String, status: Int = 200) async throws -> [CatalogModel] {
        try await CodexCatalogClient(transport: SequencedTransport([.json(status, json)]))
            .models(credentials: Self.credentials)
    }

    @Test func `the recorded catalog excludes hidden models and uses the normal context window`() async throws {
        let path = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Fixtures/Codex/models.json")
        let models = try await read(String(decoding: Data(contentsOf: path), as: UTF8.self))
        #expect(
            models.map(\.id) == [
                "gpt-6.1-sol", "gpt-6-astra", "gpt-6-sol", "gpt-6-luna", "gpt-5.6-sol", "gpt-5.6-terra", "gpt-5.6-luna"
            ])
        #expect(models.first?.contextWindow == 500_000)
        #expect(models.first?.maxOutputTokens == nil)
    }

    @Test func `the request carries the version query and only the access credential`() async throws {
        let transport = SequencedTransport([.json(200, #"{"models":[{"slug":"m"}]}"#)])
        _ = try await CodexCatalogClient(transport: transport).models(credentials: Self.credentials)
        let request = try #require(transport.sent.first)
        #expect(request.url.absoluteString == "https://chatgpt.com/backend-api/codex/models?client_version=0.163.0")
        #expect(request.method == "GET")
        let headers = Dictionary(uniqueKeysWithValues: request.headers.map { ($0.name.lowercased(), $0.value) })
        #expect(headers["authorization"] == "Bearer access-test")
        #expect(headers["chatgpt-account-id"] == "account-test")
        #expect(headers["originator"] == "ask")
        #expect(headers["accept"] == "application/json")
        #expect(!String(describing: request).contains("refresh-test"))
    }

    @Test func `server priority orders defaults and ties keep server order`() async throws {
        let models = try await read(
            #"{"models":[{"slug":"third","priority":9},{"slug":"first","priority":1},{"slug":"second","priority":1}]}"#)
        #expect(models.map(\.id) == ["first", "second", "third"])
    }

    @Test func `malformed and unavailable entries cannot displace intact text models`() async throws {
        let models = try await read(
            #"{"models":[null,7,{"slug":""},{"slug":"bad\nname"},{"slug":"hidden","visibility":"hide"},{"slug":"unavailable","supported_in_api":false},{"slug":"image-only","input_modalities":["image"]},{"slug":"ok","context_window":-1,"max_output_tokens":0},{"slug":"ok"},{"slug":"other","context_window":8192,"max_output_tokens":1024}]}"#
        )
        #expect(
            models == [CatalogModel(id: "ok"), CatalogModel(id: "other", contextWindow: 8192, maxOutputTokens: 1024)])
    }

    @Test(arguments: [#"{}"#, #"{"models":{}}"#, "<html>not JSON</html>"])
    func `an unknown response is not an empty catalog`(_ json: String) async {
        await #expect(throws: ModelCatalogError.invalidResponse) { try await read(json) }
    }

    @Test(arguments: [#"{"models":[]}"#, #"{"models":[{"slug":"hidden","visibility":"hide"}]}"#])
    func `no usable models is an actionable error`(_ json: String) async {
        await #expect(throws: ModelCatalogError.noModels) { try await read(json) }
    }

    @Test(arguments: [401, 403, 404, 429, 500])
    func `refusals expose the status but never the server body`(_ status: Int) async {
        await #expect(throws: ModelCatalogError.refused(status: status)) {
            try await read("Bearer access-test refresh-test secret", status: status)
        }
    }

    @Test func `catalog collection is bounded`() async {
        let transport = ScriptedTransport(status: 200, chunks: [String(repeating: "x", count: (2 << 20) + 1)])
        await #expect(throws: HTTPTransportError.bodyTooLarge(limit: 2 << 20)) {
            try await CodexCatalogClient(transport: transport).models(credentials: Self.credentials)
        }
    }
}
