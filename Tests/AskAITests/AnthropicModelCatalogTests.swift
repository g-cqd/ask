internal import Foundation
internal import Synchronization
internal import Testing

@testable import AskAI

struct AnthropicModelCatalogTests {
    private static let reply =
        #"{"data":[{"id":"m","max_input_tokens":64000,"capabilities":{"thinking":{"supported":true,"types":{"adaptive":{"supported":true}}}}}],"has_more":false}"#

    private func withFile(_ body: (ModelCatalogFile) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "ask-native-catalog-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try await body(ModelCatalogFile(url: root.appending(path: "models.json")))
    }

    private func catalog(
        _ transport: SequencedTransport, file: ModelCatalogFile?,
        auth: AnthropicClient.Auth = .subscription(accessToken: "fixture-one"),
        connection: UUID? = nil, endpoint: URL = AnthropicModelCatalog.endpoint
    ) -> AnthropicModelCatalog {
        AnthropicModelCatalog(
            endpoint: endpoint, cache: file, transport: transport, connectionID: connection,
            authorize: { _ in auth }, cachedAuthorization: { _ in auth })
    }

    @Test func `a fresh scoped cache avoids another request and a single lookup retains capabilities`() async throws {
        try await withFile { file in
            let transport = SequencedTransport([.json(200, Self.reply)])
            let target = catalog(transport, file: file)
            let first = try await target.models(now: 10)
            #expect(first.models.count == 1)
            #expect(first.models.first?.thinkingModes == [.adaptive])
            #expect(first.notices.isEmpty)
            #expect(try target.cached(now: 11) == first)
            let model = try target.cachedModel("m", now: 11)
            #expect(model == first.models.first)
            let absent = try target.cachedModel("absent", now: 11)
            #expect(absent == nil)
            #expect(try await target.models(now: 12) == first)
            #expect(transport.sent.count == 1)
            let mode = try FileManager.default.attributesOfItem(atPath: file.url.path)[.posixPermissions] as? NSNumber
            #expect(mode?.intValue == 0o600)
        }
    }

    @Test func `a different grant, authorization kind, registration or endpoint is a cache miss`() async throws {
        try await withFile { file in
            let transport = SequencedTransport([.json(200, Self.reply)])
            let id = UUID()
            _ = try await catalog(transport, file: file, connection: id).models(now: 10)
            let differentGrant = try catalog(
                transport, file: file, auth: .subscription(accessToken: "fixture-two"), connection: id
            )
            .cached(now: 11)
            #expect(differentGrant == nil)
            let bearer = try catalog(transport, file: file, auth: .bearer("fixture-one"), connection: id)
                .cached(now: 11)
            #expect(bearer == nil)
            let registration = try catalog(transport, file: file, connection: UUID()).cached(now: 11)
            #expect(registration == nil)
            let endpoint = try catalog(
                transport, file: file, connection: id, endpoint: URL(string: "https://other.example.test/v1/models")!
            )
            .cached(now: 11)
            #expect(endpoint == nil)
        }
    }

    @Test func `the cache stores no raw authorization value of any kind`() async throws {
        try await withFile { file in
            for auth: AnthropicClient.Auth in [
                .subscription(accessToken: "fixture-secret"), .apiKey("fixture-secret"), .bearer("fixture-secret")
            ] {
                let transport = SequencedTransport([.json(200, Self.reply)])
                _ = try await catalog(transport, file: file, auth: auth).models(now: 10)
                let text = try String(contentsOf: file.url, encoding: .utf8)
                #expect(!text.contains("fixture-secret"))
                #expect(!text.contains("Bearer "))
            }
        }
    }

    @Test func `a missing file does not ask the credential reader or create anything`() throws {
        let count = Mutex(0)
        let file = ModelCatalogFile(
            url: FileManager.default.temporaryDirectory.appending(path: "ask-absent-\(UUID()).json"))
        let transport = SequencedTransport([.json(200, Self.reply)])
        let target = AnthropicModelCatalog(
            cache: file, transport: transport, authorize: { _ in .bearer("t") },
            cachedAuthorization: { _ in
                count.withLock { $0 += 1 }
                return .bearer("t")
            })
        let cached = try target.cached(now: 1)
        let model = try target.cachedModel("m", now: 1)
        #expect(cached == nil && model == nil)
        #expect(count.withLock { $0 } == 0)
        #expect(!FileManager.default.fileExists(atPath: file.url.path))
    }

    @Test func `sign-out immediately makes cached metadata unavailable without a network`() async throws {
        try await withFile { file in
            let current = Mutex<AnthropicClient.Auth?>(.bearer("t"))
            let transport = SequencedTransport([.json(200, Self.reply)])
            let target = AnthropicModelCatalog(
                cache: file, transport: transport, authorize: { _ in .bearer("t") },
                cachedAuthorization: { _ in current.withLock { $0 } })
            _ = try await target.models(now: 10)
            current.withLock { $0 = nil }
            let cached = try target.cached(now: 11)
            let model = try target.cachedModel("m", now: 11)
            #expect(cached == nil && model == nil)
            #expect(transport.sent.count == 1)
        }
    }

    @Test func `refresh and expiry fetch again while failures preserve old bytes`() async throws {
        try await withFile { file in
            let transport = SequencedTransport([
                .json(200, Self.reply), .json(200, Self.reply), .json(500, "private body")
            ])
            let target = catalog(transport, file: file)
            _ = try await target.models(now: 10)
            _ = try await target.models(now: 11, refresh: true)
            #expect(transport.sent.count == 2)
            let before = try Data(contentsOf: file.url)
            await #expect(throws: ModelCatalogError.refused(status: 500)) { try await target.models(now: 11 + 86_400) }
            #expect(try Data(contentsOf: file.url) == before)
            #expect(transport.sent.count == 3)
        }
    }

    @Test func `broken pagination leaves downloaded models usable and preserves the old complete cache`() async throws {
        try await withFile { file in
            let transport = SequencedTransport([
                .json(200, Self.reply), .json(200, #"{"data":[{"id":"partial"}],"has_more":true}"#)
            ])
            let target = catalog(transport, file: file)
            _ = try await target.models(now: 10)
            let before = try Data(contentsOf: file.url)
            let partial = try await target.models(now: 11, refresh: true)
            #expect(partial.models.map(\.id) == ["partial"])
            #expect(!partial.notices.isEmpty)
            #expect(try Data(contentsOf: file.url) == before)
        }
    }

    @Test func `a damaged cache is reported and a new download can still be used`() async throws {
        try await withFile { file in
            try FileManager.default.createDirectory(
                at: file.url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("not json".utf8).write(to: file.url)
            let transport = SequencedTransport([.json(200, Self.reply)])
            let result = try await catalog(transport, file: file).models(now: 10)
            #expect(result.models.count == 1)
            #expect(result.notices.contains { $0.contains("Cached catalog not used") })
        }
    }

    @Test(arguments: [
        "https://user:fixture-secret@example.test/v1/models", "https://example.test/v1/models?key=fixture-secret",
        "https://example.test/v1/models#fixture-secret"
    ])
    func `a credential-bearing address is not copied into a cache`(_ address: String) async throws {
        try await withFile { file in
            let transport = SequencedTransport([.json(200, Self.reply)])
            let result = try await catalog(transport, file: file, endpoint: URL(string: address)!).models(now: 10)
            #expect(result.models.count == 1)
            #expect(!FileManager.default.fileExists(atPath: file.url.path))
            #expect(result.notices.contains { $0.contains("not cached") })
            #expect(result.notices.allSatisfy { !$0.contains("fixture-secret") })
        }
    }

    @Test func `a failed save does not discard the downloaded descriptors`() async throws {
        try await withFile { file in
            try Data("not a directory".utf8).write(to: file.url.deletingLastPathComponent())
            let transport = SequencedTransport([.json(200, Self.reply)])
            let result = try await catalog(transport, file: file).models(now: 10)
            #expect(result.models.count == 1)
            #expect(result.notices.contains { $0.contains("could not be cached") })
        }
    }
}
