internal import Foundation
internal import Testing

@testable import AskAI

/// Reading `GET /models` from the services probed on 2026-10-20 (diary 55). The three fixtures are real answers with the long
/// fields trimmed: OpenRouter, Hugging Face's router and NVIDIA, which state limits three different ways or not at all.
struct ModelListingTests {
    private func fixture(_ name: String) throws -> [UInt8] {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Fixtures/Listings/\(name).json")
        return Array(try Data(contentsOf: url))
    }

    private func listing(_ json: String) throws -> ModelListing { try ModelListing(decoding: Array(json.utf8)) }

    private func model(_ id: String, in listing: ModelListing) throws -> CatalogModel {
        try #require(listing.models.first { $0.id == id })
    }

    @Test func `OpenRouter's window is the smaller of what the model can take and what its top provider serves`() throws
    {
        let listing = try ModelListing(decoding: fixture("openrouter"))
        #expect(listing.models.count == 9)
        #expect(listing.skipped == 0)
        let free = try model("minimax/minimax-m3.1-flash:free", in: listing)
        #expect(free.contextWindow == 1_000_000)
        #expect(free.maxOutputTokens == 524_288)
        // The model can take 1,048,576 tokens; the provider OpenRouter routes it to serves 262,144.
        let narrowed = try model("nvidia/nemotron-3.5-super-vl", in: listing)
        #expect(narrowed.contextWindow == 262_144)
        #expect(narrowed.maxOutputTokens == 235_929)
        #expect(try model("~unbiased/pareto-latest", in: listing).contextWindow == 1_048_576)
    }

    @Test func `a model whose top provider states nothing keeps the model's own window and no output limit`() throws {
        let kept = try model("typesafe/jev-router", in: ModelListing(decoding: fixture("openrouter")))
        #expect(kept.contextWindow == 1_000_000)
        #expect(kept.maxOutputTokens == nil)
    }

    @Test
    func `Hugging Face's window is the smallest any live service gives, and a service that says none is not a zero`()
        throws
    {
        let listing = try ModelListing(decoding: fixture("huggingface"))
        #expect(try model("Qwen/Qwen3.8-27B", in: listing).contextWindow == 65_536)
        #expect(try model("deepseek-ai/DeepSeek-V4.1-Flash-1017", in: listing).contextWindow == 1_048_576)
        #expect(try model("swiss-ai/Apertus-v1.5-70B", in: listing).contextWindow == nil)
        #expect(listing.models.allSatisfy { $0.maxOutputTokens == nil })
    }

    @Test func `a service that is not live does not lower the window`() throws {
        let body = #"""
            {"data":[{"id":"a/b","providers":[{"provider":"x","status":"live","context_length":200000},
                                              {"provider":"y","status":"error","context_length":4096}]}]}
            """#
        #expect(try listing(body).models.first?.contextWindow == 200_000)
    }

    @Test func `NVIDIA states no limits, and every model is still listed with unknown ones`() throws {
        let listing = try ModelListing(decoding: fixture("nvidia"))
        #expect(
            listing.models.map(\.id) == [
                "01-ai/yi-large", "adept/fuyu-8b", "ai21labs/jamba-1.5-large-instruct",
                "aisingapore/sea-lion-7b-instruct"
            ])
        #expect(listing.models.allSatisfy { $0.contextWindow == nil && $0.maxOutputTokens == nil })
        #expect(listing.models.allSatisfy { $0.reasoningLevels.isEmpty && $0.defaultReasoningLevel == nil })
    }

    @Test func `Spettro's documented context_window is read`() throws {
        // Written from ask's research notes, not from an answer with a key: it pins the reading, it does not prove Spettro's shape.
        let listing = try listing(
            #"{"data":[{"id":"spettro-fast","context_window":131072,"vision":true,"reasoning":true}]}"#)
        #expect(listing.models.first?.contextWindow == 131_072)
    }

    @Test func `the order the server lists is kept, since no service says which model is its default`() throws {
        let order = try listing(#"{"data":[{"id":"z"},{"id":"a"},{"id":"m"}]}"#).models.map(\.id)
        #expect(order == ["z", "a", "m"])
    }

    @Test func `a bad entry costs itself and is counted, not the whole list`() throws {
        let body = #"""
            {"data":[{"id":"ok"},"text",7,null,{"id":42},{"id":""},{"id":"bad id"},{"id":"ok"},{"name":"no id"},{"id":"fine-2"}]}
            """#
        let listing = try listing(body)
        #expect(listing.models.map(\.id) == ["ok", "fine-2"])
        #expect(listing.skipped == 8)
    }

    @Test(arguments: [#""big""#, "1.5", "-1", "0", "100000001", "null", "[1]", #"{"a":1}"#, "true"])
    func `a window that is not a believable whole number is unknown, and the model is still listed`(_ value: String)
        throws
    {
        let kept = try listing(#"{"data":[{"id":"m","context_length":\#(value)}]}"#)
        #expect(kept.models.first?.contextWindow == nil)
        #expect(kept.skipped == 0)
    }

    @Test(arguments: [#""not a list""#, #"{"bad":1}"#, "42", "true"])
    func `a routes field of the wrong type costs only that field`(_ routes: String) throws {
        let kept = try listing(#"{"data":[{"id":"m","context_length":32768,"providers":\#(routes)}]}"#)
        #expect(kept.models.first?.contextWindow == 32_768)
        #expect(kept.skipped == 0)
    }

    @Test func `a bad figure does not hide a good one beside it`() throws {
        let kept = try listing(#"{"data":[{"id":"m","context_length":"big","top_provider":{"context_length":32768}}]}"#)
        #expect(kept.models.first?.contextWindow == 32_768)
    }

    @Test func `the largest believed window and the smallest are kept`() throws {
        #expect(
            try listing(#"{"data":[{"id":"m","context_length":100000000}]}"#).models.first?.contextWindow == 100_000_000
        )
        #expect(try listing(#"{"data":[{"id":"m","context_length":1}]}"#).models.first?.contextWindow == 1)
    }

    @Test func `an output limit that is not below the window is not believed`() throws {
        let body = #"{"data":[{"id":"m","context_length":8000,"top_provider":{"max_completion_tokens":8000}}]}"#
        #expect(try listing(body).models.first?.maxOutputTokens == nil)
        let below = #"{"data":[{"id":"m","context_length":8000,"top_provider":{"max_completion_tokens":7999}}]}"#
        #expect(try listing(below).models.first?.maxOutputTokens == 7999)
        let none = #"{"data":[{"id":"m","top_provider":{"max_completion_tokens":4096}}]}"#
        #expect(
            try listing(none).models.first?.maxOutputTokens == 4096,
            "with no window to compare, the stated limit stands")
        let zero = #"{"data":[{"id":"m","top_provider":{"max_completion_tokens":0}}]}"#
        #expect(try listing(zero).models.first?.maxOutputTokens == nil)
    }

    @Test(arguments: ["", "[]", "{}", #"{"data":{}}"#, #"{"data":"x"}"#, #"{"models":[{"id":"a"}]}"#, "not json"])
    func `an answer that is not a data list is invalid`(_ body: String) {
        #expect(throws: ModelCatalogError.invalidResponse) { try listing(body) }
    }

    @Test func `a list with no usable id is an error, not an empty catalog`() {
        #expect(throws: ModelCatalogError.noModels) { try listing(#"{"data":[]}"#) }
        #expect(throws: ModelCatalogError.noModels) { try listing(#"{"data":[{"id":"bad id"},{}]}"#) }
    }

    @Test func `no more than the entry limit are kept, and the rest are counted`() throws {
        let entries = (0 ..< ModelListing.entryLimit + 3).map { #"{"id":"m\#($0)"}"# }.joined(separator: ",")
        let listing = try listing(#"{"data":[\#(entries)]}"#)
        #expect(listing.models.count == ModelListing.entryLimit)
        #expect(listing.skipped == 3)
    }
}
