internal import Foundation
internal import Testing

@testable import AskAI

struct ModelCatalogFileTests {
    private static let scope = ModelCatalogScope(
        provider: "codex", accountID: "account-a", endpoint: URL(string: "https://example.test/models?v=1")!)
    private static let models = [CatalogModel(id: "one", contextWindow: 8192, maxOutputTokens: 1000)]

    private func withFile(_ body: (ModelCatalogFile) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "ask-catalog-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try body(ModelCatalogFile(url: root.appending(path: "models.json")))
    }

    @Test func `a missing cache is a miss and creates nothing`() throws {
        try withFile { file in
            let loaded = try file.load(scope: Self.scope, now: 10)
            #expect(loaded == nil)
            #expect(!FileManager.default.fileExists(atPath: file.url.deletingLastPathComponent().path))
        }
    }

    @Test func `a catalog round trips with its limits and owner-only permissions`() throws {
        try withFile { file in
            try file.save(Self.models, scope: Self.scope, now: 10)
            #expect(try file.load(scope: Self.scope, now: 11) == Self.models)
            let attributes = try FileManager.default.attributesOfItem(atPath: file.url.path)
            #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
            let text = try String(contentsOf: file.url, encoding: .utf8)
            #expect(!text.contains("accessToken"))
            #expect(!text.contains("refreshToken"))
        }
    }

    @Test func `a catalog expires after a day and future dates are not fresh`() throws {
        try withFile { file in
            try file.save(Self.models, scope: Self.scope, now: 10)
            #expect(try file.load(scope: Self.scope, now: 10) == Self.models)
            #expect(try file.load(scope: Self.scope, now: 10 + 86_399) == Self.models)
            #expect(try file.load(scope: Self.scope, now: 10 + 86_400) == nil)
            #expect(try file.load(scope: Self.scope, now: 9) == nil)
        }
    }

    @Test func `a different account provider endpoint or query cannot reuse the catalog`() throws {
        try withFile { file in
            try file.save(Self.models, scope: Self.scope, now: 10)
            for scope in [
                ModelCatalogScope(
                    provider: "codex", accountID: "account-a", endpoint: Self.scope.endpoint, connectionID: UUID()),
                ModelCatalogScope(provider: "codex", accountID: "account-b", endpoint: Self.scope.endpoint),
                ModelCatalogScope(provider: "other", accountID: "account-a", endpoint: Self.scope.endpoint),
                ModelCatalogScope(
                    provider: "codex", accountID: "account-a", endpoint: URL(string: "https://other.test/models?v=1")!),
                ModelCatalogScope(
                    provider: "codex", accountID: "account-a", endpoint: URL(string: "https://example.test/models?v=2")!
                )
            ] {
                #expect(try file.load(scope: scope, now: 11) == nil)
            }
        }
    }

    @Test func `malformed and oversized caches are reported and not rewritten by reading`() throws {
        try withFile { file in
            try FileManager.default.createDirectory(
                at: file.url.deletingLastPathComponent(), withIntermediateDirectories: true)
            for bytes in [Data("{broken".utf8), Data(repeating: 120, count: (2 << 20) + 1)] {
                try bytes.write(to: file.url)
                #expect(throws: ModelCatalogError.cache(path: file.url.path)) {
                    try file.load(scope: Self.scope, now: 11)
                }
                #expect(try Data(contentsOf: file.url) == bytes)
            }
        }
    }

    @Test func `an explicit save replaces the previous catalog whole`() throws {
        try withFile { file in
            try file.save(Self.models, scope: Self.scope, now: 10)
            let replacement = [CatalogModel(id: "two")]
            try file.save(replacement, scope: Self.scope, now: 20)
            #expect(try file.load(scope: Self.scope, now: 21) == replacement)
        }
    }

    @Test func `invalid model ids limits duplicates and empty lists are never persisted`() throws {
        try withFile { file in
            for models in [
                [], [CatalogModel(id: "bad\nname")], [CatalogModel(id: "ok", contextWindow: -1)],
                [CatalogModel(id: "ok", maxOutputTokens: 0)], [CatalogModel(id: "ok"), CatalogModel(id: "ok")]
            ] {
                #expect(throws: ModelCatalogError.cache(path: file.url.path)) {
                    try file.save(models, scope: Self.scope, now: 10)
                }
            }
            #expect(!FileManager.default.fileExists(atPath: file.url.path))
        }
    }
}
