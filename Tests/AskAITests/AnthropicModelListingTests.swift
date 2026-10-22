internal import AemiJSON
internal import Foundation
internal import Testing

@testable import AskAI

/// Native metadata from a real /v1/models reply, trimmed to four entries and the fields consumed (diary 2026-10-22-04).
struct AnthropicModelListingTests {
    private func page(_ body: String) throws -> AnthropicModelListing {
        try AnthropicModelListing(decoding: Array(body.utf8))
    }

    private func recorded() throws -> AnthropicModelListing {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Fixtures/Anthropic/model-catalog.json")
        return try AnthropicModelListing(decoding: Array(Data(contentsOf: url)))
    }

    @Test func `native limits and preferred thinking modes are read without a model-name table`() throws {
        let listing = try recorded()
        #expect(listing.models.count == 4)
        let sonnet = try #require(listing.models.first { $0.id == "claude-sonnet-5-5" })
        #expect(sonnet.contextWindow == 1_000_000)
        #expect(sonnet.maxOutputTokens == 128_000)
        #expect(sonnet.supportsThinking == true)
        #expect(Set(sonnet.thinkingModes) == [.adaptive, .betweenTools])
        #expect(sonnet.reasoningLevels == ["low", "medium", "high", "xhigh", "max"])
        #expect(sonnet.defaultReasoningLevel == nil, "the endpoint gives no default effort")
        #expect(listing.hasMore == false)
        #expect(listing.lastID == "claude-haiku-4-5-20251001")
    }

    @Test func `other models keep different capabilities rather than inheriting the default model's`() throws {
        let listing = try recorded()
        let older = try #require(listing.models.first { $0.id == "claude-sonnet-4-6" })
        #expect(Set(older.thinkingModes) == [.enabled, .adaptive, .disabled])
        #expect(older.reasoningLevels == ["low", "medium", "high", "max"])
        let budgetOnly = try #require(listing.models.first { $0.id == "claude-haiku-4-5-20251001" })
        #expect(budgetOnly.contextWindow == 200_000)
        #expect(budgetOnly.maxOutputTokens == 64_000)
        #expect(Set(budgetOnly.thinkingModes) == [.enabled, .disabled])
        #expect(budgetOnly.reasoningLevels.isEmpty)
    }

    @Test func `false is not unknown, and missing capabilities are not a claim that thinking is absent`() throws {
        let listing = try page(
            #"{"data":[{"id":"no","capabilities":{"thinking":{"supported":false}}},{"id":"unknown"}],"has_more":false}"#
        )
        #expect(listing.models.first?.supportsThinking == false)
        #expect(listing.models.last?.supportsThinking == nil)
        #expect(listing.models.allSatisfy { $0.thinkingModes.isEmpty && $0.reasoningLevels.isEmpty })
    }

    @Test func `a damaged optional capability field costs that field, not the model`() throws {
        let listing = try page(
            #"{"data":[{"id":"m","max_input_tokens":64000,"capabilities":{"thinking":"bad","effort":{"low":{"supported":true},"high":{"supported":"yes"}}}}],"has_more":false}"#
        )
        #expect(listing.models.first?.id == "m")
        #expect(listing.models.first?.contextWindow == 64_000)
        #expect(listing.models.first?.thinkingModes == [])
        #expect(listing.models.first?.reasoningLevels == ["low"])
        #expect(listing.skipped == 0)
    }

    @Test(arguments: [#""big""#, "1.5", "-1", "0", "100000001", "null", "[1]", "true"])
    func `a limit that is not a believable whole number becomes unknown`(_ value: String) throws {
        let listing = try page(
            #"{"data":[{"id":"m","max_input_tokens":\#(value),"max_tokens":\#(value)}],"has_more":false}"#)
        #expect(listing.models.first?.id == "m")
        #expect(listing.models.first?.contextWindow == nil)
        #expect(listing.models.first?.maxOutputTokens == nil)
    }

    @Test func `a bad id or record costs itself and a repeated id keeps the first record`() throws {
        let listing = try page(
            #"{"data":[{"id":"ok","max_tokens":1024},42,null,"bad",{}, {"id":"bad id"},{"id":"ok","max_tokens":9000},{"id":"last"}],"has_more":false}"#
        )
        #expect(listing.models.map(\.id) == ["ok", "last"])
        #expect(listing.models.first?.maxOutputTokens == 1024)
        #expect(listing.skipped == 6)
    }

    @Test(arguments: ["", "[]", "{}", #"{"data":{}}"#, #"{"data":null}"#, "not json"])
    func `a response without a data array is not a model-list page`(_ body: String) {
        #expect(throws: ModelCatalogError.invalidResponse) { try page(body) }
    }

    @Test func `an empty page is valid so a client can judge pagination`() throws {
        let listing = try page(#"{"data":[],"has_more":true,"last_id":"cursor"}"#)
        #expect(listing.models.isEmpty)
        #expect(listing.hasMore == true)
        #expect(listing.lastID == "cursor")
    }

    @Test(arguments: [#""false""#, "42", "null", "[]"])
    func `bad pagination metadata is unknown without discarding the intact models`(_ value: String) throws {
        let listing = try page(#"{"data":[{"id":"m"}],"has_more":\#(value),"last_id":42}"#)
        #expect(listing.models.map(\.id) == ["m"])
        #expect(listing.hasMore == nil)
        #expect(listing.lastID == nil)
    }

    @Test func `future mode names are not guessed, while known positive mode flags survive`() throws {
        let listing = try page(
            #"{"data":[{"id":"m","capabilities":{"thinking":{"supported":true,"types":{"adaptive":{"supported":true},"disabled":{"supported":false},"future_mode":{"supported":true}}}}}],"has_more":false}"#
        )
        #expect(listing.models.first?.thinkingModes == [.adaptive])
    }

    @Test func `old cached model descriptors still decode as unknown capability metadata`() throws {
        let decoded = try AemiJSON.JSONDecoder()
            .decode(CatalogModel.self, from: Array(#"{"id":"old","contextWindow":8192}"#.utf8))
        #expect(decoded.supportsThinking == nil)
        #expect(decoded.thinkingModes.isEmpty)
    }

    @Test func `capability metadata round-trips as data and duplicate modes are invalid`() throws {
        let original = CatalogModel(
            id: "m", reasoningLevels: ["low", "high"], supportsThinking: true, thinkingModes: [.adaptive, .betweenTools]
        )
        let bytes = try AemiJSON.JSONEncoder().encodeToBytes(original)
        let decoded = try AemiJSON.JSONDecoder().decode(CatalogModel.self, from: bytes)
        #expect(decoded == original)
        #expect(!CatalogModel(id: "m", thinkingModes: [.adaptive, .adaptive]).isValid)
    }
}
