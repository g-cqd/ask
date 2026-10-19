internal import Foundation
internal import Testing

@testable import AskAI

struct CodexModelCatalogTests {
    private static let reply = #"{"models":[{"slug":"live-model","context_window":12000}]}"#
    private static let credentials = CodexCredentials(
        accessToken: "access-one", refreshToken: "refresh-one", expiresAt: 1_000_000, accountID: "account-one")

    private func withFiles(_ body: (CredentialFile, ModelCatalogFile) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "ask-discovery-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let credentials = CredentialFile(url: root.appending(path: "credentials.json"))
        try credentials.saveCodex(Self.credentials)
        try await body(credentials, ModelCatalogFile(url: root.appending(path: "models.json")))
    }

    @Test func `a download is cached and a fresh cache sends no second request`() async throws {
        try await withFiles { file, cache in
            let transport = SequencedTransport([.json(200, Self.reply)])
            let catalog = CodexModelCatalog(credentials: file, cache: cache, transport: transport)
            let first = try await catalog.models(now: 10)
            #expect(first.models == [CatalogModel(id: "live-model", contextWindow: 12000)])
            #expect(first.notices.isEmpty)
            #expect(try catalog.cached(now: 11) == first)
            #expect(try await catalog.models(now: 11) == first)
            #expect(transport.sent.count == 1)
        }
    }

    @Test func `explicit refresh and expiry fetch new catalogs`() async throws {
        try await withFiles { file, cache in
            let transport = SequencedTransport([.json(200, Self.reply), .json(200, #"{"models":[{"slug":"new"}]}"#)])
            let catalog = CodexModelCatalog(credentials: file, cache: cache, transport: transport)
            _ = try await catalog.models(now: 10)
            #expect(try await catalog.models(now: 11, refresh: true).models.map(\.id) == ["new"])
            _ = try await catalog.models(now: 11 + 86_400)
            #expect(transport.sent.count == 3)
        }
    }

    @Test func `a cache never outlives sign-out or follows a different account`() async throws {
        try await withFiles { file, cache in
            let transport = SequencedTransport([.json(200, Self.reply)])
            let catalog = CodexModelCatalog(credentials: file, cache: cache, transport: transport)
            _ = try await catalog.models(now: 10)
            try file.removeCodex()
            #expect(try catalog.cached(now: 11) == nil)
            await #expect(throws: CodexAccessError.signedOut) { try await catalog.models(now: 11) }
            try file.saveCodex(
                CodexCredentials(
                    accessToken: "access-two", refreshToken: "refresh-two", expiresAt: 1_000_000,
                    accountID: "account-two"))
            #expect(try catalog.cached(now: 12) == nil)
            _ = try await catalog.models(now: 12)
            #expect(transport.sent.count == 2)
            #expect(
                transport.sent.last?.headers.contains { $0.name == "chatgpt-account-id" && $0.value == "account-two" }
                    == true)
        }
    }

    @Test func `a failed refresh preserves the last cache and never silently uses it`() async throws {
        try await withFiles { file, cache in
            let transport = SequencedTransport([.json(200, Self.reply), .json(403, "refused")])
            let catalog = CodexModelCatalog(credentials: file, cache: cache, transport: transport)
            let first = try await catalog.models(now: 10)
            let bytes = try Data(contentsOf: cache.url)
            await #expect(throws: ModelCatalogError.refused(status: 403)) {
                try await catalog.models(now: 11, refresh: true)
            }
            #expect(try Data(contentsOf: cache.url) == bytes)
            #expect(try catalog.cached(now: 12) == first)
        }
    }

    @Test func `cache damage is reported and a valid download remains usable`() async throws {
        try await withFiles { file, cache in
            try Data("{bad".utf8).write(to: cache.url)
            let catalog = CodexModelCatalog(
                credentials: file, cache: cache, transport: SequencedTransport([.json(200, Self.reply)]))
            let result = try await catalog.models(now: 10)
            #expect(result.models.map(\.id) == ["live-model"])
            #expect(result.notices.count == 1)
            #expect(try catalog.cached(now: 11)?.models == result.models)
        }
    }

    @Test func `an unwritable cache does not discard a successful download`() async throws {
        try await withFiles { file, cache in
            try Data("not a directory".utf8).write(to: cache.url)
            let blocked = ModelCatalogFile(url: cache.url.appending(path: "child.json"))
            let catalog = CodexModelCatalog(
                credentials: file, cache: blocked, transport: SequencedTransport([.json(200, Self.reply)]))
            let result = try await catalog.models(now: 10)
            #expect(result.models.map(\.id) == ["live-model"])
            #expect(result.notices.count == 1)
        }
    }
}
