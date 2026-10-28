internal import Foundation
internal import Testing

@testable import AskAI

@Suite("The filter of models by usefulness (roadmap 0089)")
struct ModelUsefulnessTests {
    private let models = [
        CatalogModel(id: "chat"), CatalogModel(id: "image", unsuitable: "image generation"),
        CatalogModel(id: "tab", unsuitable: "tab completion")
    ]

    @Test func `on, the marked models are left out and the rest keep their order`() {
        #expect(ModelUsefulness.shown(models, onlyUseful: true).map(\.id) == ["chat"])
    }

    @Test func `off, every model of the provider is listed`() {
        #expect(ModelUsefulness.shown(models, onlyUseful: false).map(\.id) == ["chat", "image", "tab"])
    }

    @Test func `the hidden ones are named with their reasons`() {
        #expect(ModelUsefulness.hidden(models).map(\.unsuitable) == ["image generation", "tab completion"])
    }

    @Test func `a model whose catalog says nothing is useful, not hidden`() {
        #expect(ModelUsefulness.shown([CatalogModel(id: "plain")], onlyUseful: true).count == 1)
    }

    @Test func `the mark survives the cache`() throws {
        let stored = try JSONDecoder()
            .decode(
                [CatalogModel].self, from: JSONEncoder().encode(models))
        #expect(stored == models)
        let old = try JSONDecoder().decode(CatalogModel.self, from: Data(#"{"id":"x"}"#.utf8))
        #expect(old.unsuitable == nil, "a cache written before the mark existed lists everything, as it did")
    }

    @Test func `OpenRouter's output modality marks a model that gives no text`() throws {
        let body = #"""
            {"data":[{"id":"a/text","architecture":{"modality":"text+image->text"}},
            {"id":"a/draw","architecture":{"modality":"text->image"}},
            {"id":"a/mixed","architecture":{"modality":"text->text+image"}},
            {"id":"a/none"},{"id":"a/odd","architecture":{"modality":"text"}}]}
            """#
        let listing = try ModelListing(decoding: Array(body.utf8))
        let marks = Dictionary(uniqueKeysWithValues: listing.models.map { ($0.id, $0.unsuitable) })
        #expect(marks["a/draw"] == "does not produce text")
        #expect(["a/text", "a/mixed", "a/none", "a/odd"].allSatisfy { (marks[$0] ?? nil) == nil })
        #expect(marks.count == 5)
    }

    @Test func `the recorded OpenRouter list marks nothing: every entry there gives text`() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Fixtures/Listings/openrouter.json")
        let listing = try ModelListing(decoding: Array(Data(contentsOf: url)))
        #expect(ModelUsefulness.hidden(listing.models).isEmpty)
    }
}
