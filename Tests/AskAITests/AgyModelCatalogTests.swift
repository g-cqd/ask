internal import Foundation
internal import Testing

@testable import AskAI

/// The Antigravity model list and its cache: bound to the project it was requested for, read without a network, kept for a day.
struct AgyModelCatalogTests {
    private let world = AgyAccessWorld()
    private let cacheFile = ModelCatalogFile(
        url: FileManager.default.temporaryDirectory.appending(
            path: "ask-agy-catalog-\(UUID().uuidString)/models-agy.json"))

    private static func list() throws -> String {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Fixtures/Agy/model-list.json")
        return String(decoding: try Data(contentsOf: url), as: UTF8.self)
    }

    private func catalog(_ transport: any HTTPTransport) -> AgyModelCatalog {
        AgyModelCatalog(
            credentials: world.file, cache: cacheFile, cloud: AgyCloudClient(transport: transport),
            access: world.access(transport))
    }

    private func scope(project: String = "proj-0") -> ModelCatalogScope {
        ModelCatalogScope(provider: "agy", accountID: project, endpoint: AgyModelCatalog.endpoint)
    }

    @Test func `a refresh downloads the list, returns it with the server's default, and keeps it`() async throws {
        try world.file.saveAgy(world.valid)
        let transport = SequencedTransport([.json(200, try Self.list())])
        let listing = try await catalog(transport).refreshed(now: 5_000)
        #expect(listing.snapshot.models.count == 21 && listing.snapshot.notices.isEmpty)
        #expect(listing.defaultModelID == "gemini-4-argon-medium")
        let sent = try #require(transport.sent.first)
        #expect(sent.url == AgyModelCatalog.endpoint)
        #expect(sent.headers.contains { $0.name == "authorization" && $0.value == "Bearer at-ok" })
        #expect(try cacheFile.load(scope: scope(), now: 5_000)?.count == 21)
    }

    @Test func `the cache is read with no request, and says what the download did`() async throws {
        try world.file.saveAgy(world.valid)
        let downloaded = try await catalog(SequencedTransport([.json(200, try Self.list())])).refreshed(now: 5_000)
        let silent = SequencedTransport([.json(500, "no")])
        let cached = try #require(try catalog(silent).cached(now: 6_000))
        #expect(cached == CatalogSnapshot(models: downloaded.snapshot.models))
        #expect(silent.sent.isEmpty)
    }

    @Test func `one model is read from the cache with its limits, and an unlisted one is nothing`() async throws {
        try world.file.saveAgy(world.valid)
        _ = try await catalog(SequencedTransport([.json(200, try Self.list())])).refreshed(now: 5_000)
        let found = try #require(
            try catalog(SequencedTransport([.json(500, "")])).cachedModel("gpt-oss-120b-medium", now: 5_100))
        #expect(found.contextWindow == 131_072 && found.maxOutputTokens == 32_768 && found.supportsThinking == true)
        #expect(try catalog(SequencedTransport([.json(500, "")])).cachedModel("nonesuch", now: 5_100) == nil)
    }

    @Test func `nothing is cached for a stranger: signed out, not onboarded, another project, or a day old`()
        async throws
    {
        let quiet = SequencedTransport([.json(500, "")])
        #expect(try catalog(quiet).cached(now: 5_000) == nil, "signed out")
        try world.file.saveAgy(world.valid)
        _ = try await catalog(SequencedTransport([.json(200, try Self.list())])).refreshed(now: 5_000)
        #expect(try catalog(quiet).cached(now: 5_000 + 86_399) != nil)
        #expect(try catalog(quiet).cached(now: 5_000 + 86_400) == nil, "a day old")
        var other = world.valid
        other.projectID = "proj-other"
        try world.file.saveAgy(other)
        #expect(
            try catalog(quiet).cached(now: 5_100) == nil
                && catalog(quiet).cachedModel("gemini-3-flash", now: 5_100) == nil)
        var bare = world.valid
        bare.projectID = nil
        try world.file.saveAgy(bare)
        #expect(try catalog(quiet).cached(now: 5_100) == nil, "no project yet")
        #expect(quiet.sent.isEmpty)
    }

    @Test func `a damaged cache is reported and never rewritten by a read`() async throws {
        try world.file.saveAgy(world.valid)
        try FileManager.default.createDirectory(
            at: cacheFile.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{broken".utf8).write(to: cacheFile.url)
        #expect(throws: ModelCatalogError.self) { try catalog(SequencedTransport([.json(500, "")])).cached(now: 5_000) }
        #expect(throws: ModelCatalogError.self) {
            try catalog(SequencedTransport([.json(500, "")])).cachedModel("m", now: 5_000)
        }
        #expect(try Data(contentsOf: cacheFile.url) == Data("{broken".utf8))
    }

    @Test func `a failed download leaves the cache as it was`() async throws {
        try world.file.saveAgy(world.valid)
        _ = try await catalog(SequencedTransport([.json(200, try Self.list())])).refreshed(now: 5_000)
        let before = try Data(contentsOf: cacheFile.url)
        await #expect(throws: ModelCatalogError.refused(status: 503)) {
            _ = try await catalog(SequencedTransport([.json(503, "{}")])).refreshed(now: 6_000)
        }
        #expect(try Data(contentsOf: cacheFile.url) == before)
    }

    @Test func `a refresh signs in again first when the token has expired, and a signed-out account is told so`()
        async throws
    {
        try world.file.saveAgy(world.expired)
        let transport = SequencedTransport([.json(200, AgyAccessWorld.refreshed), .json(200, try Self.list())])
        _ = try await catalog(transport).refreshed(now: 5_000)
        #expect(transport.sent.count == 2)
        #expect(transport.sent[1].headers.contains { $0.name == "authorization" && $0.value == "Bearer at-2" })
        try world.file.removeAgy()
        await #expect(throws: AgyAccessError.signedOut) {
            _ = try await catalog(SequencedTransport([.json(500, "")])).refreshed(now: 5_000)
        }
    }

    @Test func `a cache that cannot be written is a notice, and the list is still returned`() async throws {
        try world.file.saveAgy(world.valid)
        let parent = FileManager.default.temporaryDirectory.appending(
            path: "ask-agy-catalog-blocked-\(UUID().uuidString)")
        try Data("x".utf8).write(to: parent)
        let blocked = ModelCatalogFile(url: parent.appending(path: "models-agy.json"))
        let catalog = AgyModelCatalog(
            credentials: world.file, cache: blocked,
            cloud: AgyCloudClient(transport: SequencedTransport([.json(200, try Self.list())])),
            access: world.access(SequencedTransport([.json(500, "")])))
        let listing = try await catalog.refreshed(now: 5_000)
        #expect(listing.snapshot.models.count == 21)
        #expect(listing.snapshot.notices.count == 1 && listing.snapshot.notices[0].contains("could not be cached"))
    }

    @Test func `the cache holds no token and no secret`() async throws {
        try world.file.saveAgy(world.valid)
        _ = try await catalog(SequencedTransport([.json(200, try Self.list())])).refreshed(now: 5_000)
        let text = String(decoding: try Data(contentsOf: cacheFile.url), as: UTF8.self)
        for secret in ["at-ok", "rt-1", "secret-1"] { #expect(!text.contains(secret), "\(secret)") }
    }

    @Test
    func
        `a damaged entry elsewhere in the cache costs a run's own model nothing, and is still reported by a full read`()
        async throws
    {
        try world.file.saveAgy(world.valid)
        _ = try await catalog(SequencedTransport([.json(200, try Self.list())])).refreshed(now: 5_000)
        let whole = String(decoding: try Data(contentsOf: cacheFile.url), as: UTF8.self)
        let damaged = whole.replacingOccurrences(
            of: #""models":["#, with: #""models":[{"id":"bad id","contextWindow":-1},"#)
        #expect(damaged != whole)
        try Data(damaged.utf8).write(to: cacheFile.url)
        let quiet = SequencedTransport([.json(500, "")])
        #expect(try catalog(quiet).cachedModel("gemini-3-flash", now: 5_100)?.contextWindow == 1_048_576)
        #expect(throws: ModelCatalogError.self) { try catalog(quiet).cached(now: 5_100) }
    }
}
