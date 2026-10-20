internal import Foundation
internal import Testing

@testable import AskAI

/// Finding one model in a cached catalog without decoding the rest. A run needs one model and a list can hold hundreds: reading
/// them all cost 2 ms of a 12 ms start with OpenRouter's 468 (diary 55).
struct ModelCatalogLookupTests {
    private static let scope = ModelCatalogScope(
        provider: "p", accountID: "api-key", endpoint: URL(string: "https://example.test/v1/models")!)
    private static let models = [
        CatalogModel(id: "org/first", contextWindow: 8192, maxOutputTokens: 1000),
        CatalogModel(id: "second"),
        CatalogModel(
            id: "third:free", contextWindow: 1_000_000, reasoningLevels: ["low", "high"], defaultReasoningLevel: "low"),
        CatalogModel(id: "~last", contextWindow: 32768)
    ]

    private func withFile(_ body: (ModelCatalogFile) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "ask-lookup-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let file = ModelCatalogFile(url: root.appending(path: "models.json"))
        try file.save(Self.models, scope: Self.scope, now: 10)
        try body(file)
    }

    @Test func `every model comes back exactly as a full load gives it`() throws {
        try withFile { file in
            let loaded = try #require(try file.load(scope: Self.scope, now: 11))
            for model in loaded { #expect(try file.model(model.id, scope: Self.scope, now: 11) == model) }
            #expect(loaded == Self.models)
        }
    }

    @Test func `a model the catalog does not list is nil, not an error`() throws {
        try withFile { file in
            let found1 = try file.model("missing", scope: Self.scope, now: 11)
            #expect(found1 == nil)
            let found2 = try file.model("org", scope: Self.scope, now: 11)
            #expect(found2 == nil, "an id is matched whole, not by prefix")
            let found3 = try file.model("", scope: Self.scope, now: 11)
            #expect(found3 == nil)
        }
    }

    @Test func `an absent, expired, future or foreign catalog is a miss`() throws {
        try withFile { file in
            let found4 = try file.model("second", scope: Self.scope, now: 10 + 86_399)
            #expect(found4 != nil)
            let found5 = try file.model("second", scope: Self.scope, now: 10 + 86_400)
            #expect(found5 == nil)
            let found6 = try file.model("second", scope: Self.scope, now: 9)
            #expect(found6 == nil)
            let found7 = try file.model("second", scope: Self.scope, now: .nan)
            #expect(found7 == nil)
            let other = ModelCatalogScope(provider: "q", accountID: "api-key", endpoint: Self.scope.endpoint)
            let found8 = try file.model("second", scope: other, now: 11)
            #expect(found8 == nil)
            let elsewhere = ModelCatalogScope(
                provider: "p", accountID: "api-key", endpoint: URL(string: "https://other.test/v1/models")!)
            let found9 = try file.model("second", scope: elsewhere, now: 11)
            #expect(found9 == nil)
            let keyless = ModelCatalogScope(provider: "p", accountID: "no-key", endpoint: Self.scope.endpoint)
            let found10 = try file.model("second", scope: keyless, now: 11)
            #expect(found10 == nil)
        }
        let absent = ModelCatalogFile(
            url: FileManager.default.temporaryDirectory.appending(path: "ask-none-\(UUID()).json"))
        let found11 = try absent.model("second", scope: Self.scope, now: 11)
        #expect(found11 == nil)
    }

    @Test func `a damaged entry elsewhere costs nothing, and the damaged one itself is an error`() throws {
        try withFile { file in
            var text = try String(contentsOf: file.url, encoding: .utf8)
            #expect(text.contains(#""id":"second""#))
            text = text.replacingOccurrences(of: #""id":"second""#, with: #""id":"bad id""#)
            try text.write(to: file.url, atomically: true, encoding: .utf8)
            #expect(try file.model("org/first", scope: Self.scope, now: 11)?.contextWindow == 8192)
            #expect(try file.model("~last", scope: Self.scope, now: 11)?.contextWindow == 32768)
            #expect(throws: ModelCatalogError.cache(path: file.url.path)) {
                try file.model("bad id", scope: Self.scope, now: 11)
            }
            #expect(throws: ModelCatalogError.cache(path: file.url.path)) { try file.load(scope: Self.scope, now: 11) }
        }
    }

    @Test func `an entry with a limit that is not positive is an error, as in a full load`() throws {
        try withFile { file in
            let text = try String(contentsOf: file.url, encoding: .utf8)
                .replacingOccurrences(of: #""contextWindow":8192"#, with: #""contextWindow":0"#)
            try text.write(to: file.url, atomically: true, encoding: .utf8)
            #expect(throws: ModelCatalogError.cache(path: file.url.path)) {
                try file.model("org/first", scope: Self.scope, now: 11)
            }
        }
    }

    @Test func `a catalog of another version is an error, though its header is otherwise good`() throws {
        try withFile { file in
            let text = try String(contentsOf: file.url, encoding: .utf8)
            #expect(text.contains(#""version":1"#))
            try text.replacingOccurrences(of: #""version":1"#, with: #""version":2"#)
                .write(
                    to: file.url, atomically: true, encoding: .utf8)
            #expect(throws: ModelCatalogError.cache(path: file.url.path)) {
                try file.model("second", scope: Self.scope, now: 11)
            }
            #expect(throws: ModelCatalogError.cache(path: file.url.path)) { try file.load(scope: Self.scope, now: 11) }
        }
    }

    @Test func `a catalog whose models are not a list is an error, though its header is good`() throws {
        try withFile { file in
            let text = try String(contentsOf: file.url, encoding: .utf8)
            let start = try #require(text.range(of: #""models":"#))
            #expect(text.hasSuffix("]}"))
            try (String(text[..<start.lowerBound]) + #""models":{}}"#)
                .write(to: file.url, atomically: true, encoding: .utf8)
            #expect(throws: ModelCatalogError.cache(path: file.url.path)) {
                try file.model("second", scope: Self.scope, now: 11)
            }
        }
    }

    @Test(arguments: ["", "not json", "[]", "{}", #"{"version":2,"scope":{},"fetchedAt":1,"models":[]}"#])
    func `a file that is not a catalog is an error`(_ content: String) throws {
        try withFile { file in
            try content.write(to: file.url, atomically: true, encoding: .utf8)
            #expect(throws: ModelCatalogError.cache(path: file.url.path)) {
                try file.model("second", scope: Self.scope, now: 11)
            }
        }
    }

    @Test func `a file that is not a regular file of believable size is an error`() throws {
        try withFile { file in
            try Data(count: (2 << 20) + 1).write(to: file.url)
            #expect(throws: ModelCatalogError.cache(path: file.url.path)) {
                try file.model("second", scope: Self.scope, now: 11)
            }
            try FileManager.default.removeItem(at: file.url)
            try FileManager.default.createDirectory(at: file.url, withIntermediateDirectories: false)
            #expect(throws: ModelCatalogError.cache(path: file.url.path)) {
                try file.model("second", scope: Self.scope, now: 11)
            }
        }
    }

    @Test func `the provider's catalog finds one model of its cache without a network`() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "ask-lookup-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let transport = SequencedTransport([.json(200, #"{"data":[{"id":"a/b","context_length":64000},{"id":"c"}]}"#)])
        let catalog = ProviderModelCatalog(
            name: "p", baseURL: URL(string: "https://example.test/v1")!, apiKey: "k", headers: [:],
            cache: ModelCatalogFile(url: root.appending(path: "models-p.json")), transport: transport)
        let found12 = try catalog.cachedModel("a/b", now: 10)
        #expect(found12 == nil)
        _ = try await catalog.models(now: 10)
        #expect(try catalog.cachedModel("a/b", now: 11)?.contextWindow == 64000)
        #expect(try catalog.cachedModel("c", now: 11)?.contextWindow == nil)
        let found13 = try catalog.cachedModel("zzz", now: 11)
        #expect(found13 == nil)
        #expect(transport.sent.count == 1)
        let uncached = ProviderModelCatalog(
            name: "p", baseURL: URL(string: "https://example.test/v1")!, apiKey: nil, headers: [:], cache: nil,
            transport: transport)
        let found14 = try uncached.cachedModel("a/b", now: 11)
        #expect(found14 == nil)
    }
}
