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

    @Test func `the recorded catalog reports each model's reasoning levels and default, in the server's order`()
        async throws
    {
        let path = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Fixtures/Codex/models.json")
        let models = try await read(String(decoding: Data(contentsOf: path), as: UTF8.self))
        let byID = Dictionary(uniqueKeysWithValues: models.map { ($0.id, $0) })
        let full = ["low", "medium", "high", "xhigh", "max", "ultra"]
        #expect(byID["gpt-6.1-sol"]?.reasoningLevels == full)
        #expect(byID["gpt-6.1-sol"]?.defaultReasoningLevel == "low")
        #expect(byID["gpt-6-sol"]?.defaultReasoningLevel == "medium")
        // The luna models stop at max, and none of the nine offers an "off".
        #expect(byID["gpt-6-luna"]?.reasoningLevels == ["low", "medium", "high", "xhigh", "max"])
        #expect(byID["gpt-5.6-luna"]?.reasoningLevels == ["low", "medium", "high", "xhigh", "max"])
        #expect(models.allSatisfy { !$0.reasoningLevels.contains("none") && !$0.reasoningLevels.contains("off") })
    }

    @Test func `levels may be objects or plain strings, and dirty or repeated names are dropped`() async throws {
        let json =
            #"{"models":[{"slug":"a","supported_reasoning_levels":[{"effort":"low","description":"d"},"medium",{"effort":"low"},{"effort":"Bad Level"},{"effort":"has space"},{"effort":"HIGH"},"Max","hi-gh","hi_gh","hi[gh",{"effort":""},{"nope":1},7,null,"hi\u0000gh","xhigh"]}]}"#
        let models = try await read(json)
        #expect(models.first?.reasoningLevels == ["low", "medium", "xhigh"])
    }

    @Test func `a very long level name or a very long list cannot grow the catalog`() async throws {
        let long = String(repeating: "a", count: 25)
        let letters = Array("abcdefghijklmnopqrstuvwxyz")
        var names: [String] = []
        for index in 0 ..< 40 {
            let first = String(letters[index % 26])
            let second = String(letters[index / 26])
            names.append("l" + first + second)
        }
        let many = names.map { #"{"effort":"\#($0)"}"# }.joined(separator: ",")
        let models = try await read(
            #"{"models":[{"slug":"a","supported_reasoning_levels":[{"effort":"\#(long)"},"ok"]},{"slug":"b","supported_reasoning_levels":[\#(many)]}]}"#
        )
        #expect(models.first?.reasoningLevels == ["ok"])
        #expect(models.last?.reasoningLevels == Array(names.prefix(16)), "the first 16 valid names, in order")
    }

    @Test func `a default that is not one of the reported levels is ignored, and no levels is unknown`() async throws {
        let models = try await read(
            #"{"models":[{"slug":"a","default_reasoning_level":"turbo","supported_reasoning_levels":[{"effort":"low"}]},{"slug":"b","default_reasoning_level":"low"},{"slug":"c"}]}"#
        )
        #expect(models[0].defaultReasoningLevel == nil)
        #expect(models[1].reasoningLevels.isEmpty, "not reported is not the same as none")
        #expect(models[1].defaultReasoningLevel == nil, "a default with no list to belong to is not trusted")
        #expect(models[2].reasoningLevels.isEmpty && models[2].defaultReasoningLevel == nil)
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
