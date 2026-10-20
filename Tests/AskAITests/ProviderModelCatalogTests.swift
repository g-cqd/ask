internal import Foundation
internal import Testing

@testable import AskAI

/// Reading and keeping a provider's `GET /models`: what is sent, what a key may and may not do, and what a failure leaves behind.
struct ProviderModelCatalogTests {
    private static let list = #"{"data":[{"id":"org/m","context_length":64000},{"id":"n"}]}"#
    private static let base = URL(string: "https://api.example.test/v1")!

    private func withCache(_ body: (ModelCatalogFile) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "ask-provider-catalog-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try await body(ModelCatalogFile(url: root.appending(path: "models-p.json")))
    }

    private func catalog(
        _ transport: SequencedTransport, cache: ModelCatalogFile?, key: String? = "sk-one", base: URL = base,
        name: String = "p", headers: [String: String] = [:]
    ) -> ProviderModelCatalog {
        ProviderModelCatalog(
            name: name, baseURL: base, apiKey: key, headers: headers, cache: cache, transport: transport)
    }

    @Test func `the list is read from models beneath the base, with the key, and keeps the window the server states`()
        async throws
    {
        try await withCache { cache in
            let transport = SequencedTransport([.json(200, Self.list)])
            let snapshot = try await catalog(transport, cache: cache, headers: ["x-gateway": "g"]).models(now: 10)
            #expect(snapshot.models.map(\.id) == ["org/m", "n"])
            #expect(snapshot.models.first?.contextWindow == 64000)
            #expect(snapshot.notices.isEmpty)
            let request = try #require(transport.sent.first)
            #expect(request.method == "GET")
            #expect(request.url.absoluteString == "https://api.example.test/v1/models")
            #expect(request.headers.contains { $0.name == "authorization" && $0.value == "Bearer sk-one" })
            #expect(request.headers.contains { $0.name == "x-gateway" && $0.value == "g" })
        }
    }

    @Test(arguments: [nil, ""] as [String?])
    func `a service listed without a key is asked without one`(_ key: String?) async throws {
        let transport = SequencedTransport([.json(200, Self.list)])
        _ = try await catalog(transport, cache: nil, key: key).models(now: 10)
        #expect(try #require(transport.sent.first).headers.allSatisfy { $0.name != "authorization" })
    }

    @Test func `a fresh cache sends nothing, a refresh and a day's age send again`() async throws {
        try await withCache { cache in
            let transport = SequencedTransport([.json(200, Self.list), .json(200, #"{"data":[{"id":"new"}]}"#)])
            let target = catalog(transport, cache: cache)
            let first = try await target.models(now: 10)
            #expect(try target.cached(now: 11) == first)
            #expect(try await target.models(now: 11) == first)
            #expect(transport.sent.count == 1)
            #expect(try await target.models(now: 12, refresh: true).models.map(\.id) == ["new"])
            _ = try await target.models(now: 12 + 86_400)
            #expect(transport.sent.count == 3)
        }
    }

    @Test func `a cache belongs to one provider, one endpoint, and whether a key was sent`() async throws {
        try await withCache { cache in
            let transport = SequencedTransport([.json(200, Self.list)])
            _ = try await catalog(transport, cache: cache).models(now: 10)
            #expect(try catalog(transport, cache: cache).cached(now: 11) != nil)
            #expect(try catalog(transport, cache: cache, name: "other").cached(now: 11) == nil)
            #expect(
                try catalog(transport, cache: cache, base: URL(string: "https://elsewhere.test/v1")!).cached(now: 11)
                    == nil)
            #expect(try catalog(transport, cache: cache, key: nil).cached(now: 11) == nil)
        }
    }

    @Test func `the key is never written to the cache`() async throws {
        try await withCache { cache in
            let transport = SequencedTransport([.json(200, Self.list)])
            _ = try await catalog(transport, cache: cache, key: "sk-secret-value").models(now: 10)
            let stored = String(decoding: try Data(contentsOf: cache.url), as: UTF8.self)
            #expect(!stored.contains("sk-secret-value"))
            #expect(!stored.lowercased().contains("bearer"))
        }
    }

    @Test(arguments: [
        "https://user:fixture-secret@example.test/v1", "https://fixture-secret@example.test/v1",
        "https://example.test/v1?api_key=fixture-secret", "https://example.test/v1#fixture-secret"
    ])
    func `an address that could carry a credential lists without caching the address`(_ address: String) async throws {
        try await withCache { cache in
            let transport = SequencedTransport([.json(200, Self.list)])
            let base = try #require(URL(string: address))
            let target = catalog(transport, cache: cache, base: base)
            let snapshot = try await target.models(now: 10)
            #expect(snapshot.models.count == 2)
            #expect(snapshot.notices.count == 1)
            #expect(snapshot.notices.first?.contains("not cached") == true)
            #expect(snapshot.notices.allSatisfy { !$0.contains("fixture-secret") })
            #expect(!FileManager.default.fileExists(atPath: cache.url.path))
            let cached = try target.cached(now: 11)
            #expect(cached == nil)
        }
    }

    @Test(arguments: [401, 403, 404, 429, 500])
    func `a refusal names the status, not the body, and leaves the cache as it was`(_ status: Int) async throws {
        try await withCache { cache in
            let transport = SequencedTransport([.json(200, Self.list), .json(status, "sk-one is not allowed")])
            let target = catalog(transport, cache: cache)
            let kept = try await target.models(now: 10)
            await #expect(throws: ModelCatalogError.refused(status: status)) {
                try await target.models(now: 11, refresh: true)
            }
            #expect(try target.cached(now: 12) == kept)
        }
    }

    @Test func `a damaged cache is reported and the download still serves the run`() async throws {
        try await withCache { cache in
            try FileManager.default.createDirectory(
                at: cache.url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("not json".utf8).write(to: cache.url)
            let transport = SequencedTransport([.json(200, Self.list)])
            let snapshot = try await catalog(transport, cache: cache).models(now: 10)
            #expect(snapshot.models.count == 2)
            #expect(snapshot.notices.count == 1)
            #expect(snapshot.notices.first?.hasPrefix("Cached catalog not used") == true)
        }
    }

    @Test func `entries left out are said, and an answer with none usable is an error`() async throws {
        let transport = SequencedTransport([
            .json(200, #"{"data":[{"id":"ok"},{"id":"bad id"}]}"#), .json(200, #"{"data":[]}"#)
        ])
        let target = catalog(transport, cache: nil)
        let snapshot = try await target.models(now: 10)
        #expect(snapshot.notices == ["1 listed entries were left out: no usable id, a repeat, or the catalog limit."])
        await #expect(throws: ModelCatalogError.noModels) { try await target.models(now: 10) }
    }

    @Test func `with no cache a download is not an error and a cached read is empty`() async throws {
        let transport = SequencedTransport([.json(200, Self.list)])
        let target = catalog(transport, cache: nil)
        #expect(try target.cached(now: 10) == nil)
        #expect(try await target.models(now: 10).notices.isEmpty)
    }

    @Test func `a transport failure is the caller's to name`() async {
        struct Down: Error, Equatable {}
        let target = catalog(SequencedTransport([.failure(Down())]), cache: nil)
        await #expect(throws: Down()) { try await target.models(now: 10) }
    }
}
