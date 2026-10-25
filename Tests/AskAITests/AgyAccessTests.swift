internal import Foundation
internal import Testing

@testable import AskAI

/// Using stored Antigravity credentials: returned while they last, refreshed when they do not, and onboarded once.
///
/// Google did not rotate the refresh token in the one refresh observed (ADR-0075), so no lock is needed for correctness: a save
/// that finds the stored record changed leaves it alone.
struct AgyAccessTests {
    private let world = AgyAccessWorld()

    @Test func `credentials that have not expired are used without a request`() async throws {
        try world.file.saveAgy(world.valid)
        let transport = SequencedTransport([.json(500, "no")])
        let session = try await world.access(transport).session(now: 5_000)
        #expect(session == AgySession(accessToken: "at-ok", projectID: "proj-0"))
        #expect(transport.sent.isEmpty)
    }

    @Test func `nothing stored is signed out`() async {
        await #expect(throws: AgyAccessError.signedOut) {
            _ = try await world.access(SequencedTransport([.json(500, "")])).session(now: 1)
        }
    }

    @Test func `a damaged file is reported, never read as signed out`() async throws {
        try FileManager.default.createDirectory(
            at: world.file.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{broken".utf8).write(to: world.file.url)
        do { _ = try await world.access(SequencedTransport([.json(500, "")])).session(now: 1) } catch {
            guard case .storage = error else {
                Issue.record("expected storage, got \(error)")
                return
            }
            return
        }
        Issue.record("a damaged file was read as something")
    }

    @Test func `an expired token is refreshed with the stored secret, and the refresh token and secret are kept`()
        async throws
    {
        try world.file.saveAgy(world.expired)
        let transport = SequencedTransport([.json(200, AgyAccessWorld.refreshed)])
        let session = try await world.access(transport).session(now: 5_000)
        #expect(session == AgySession(accessToken: "at-2", projectID: "proj-0"))
        let stored = try #require(try world.file.loadAgy())
        #expect(stored.accessToken == "at-2" && stored.refreshToken == "rt-1" && stored.clientSecret == "secret-1")
        #expect(stored.expiresAt > 5_000 && stored.projectID == "proj-0" && stored.tierID == "t")
        #expect(transport.sent.count == 1)
        let sent = world.body(try #require(transport.sent.first))
        #expect(sent.contains("grant_type=refresh_token") && sent.contains("client_secret=secret-1"))
    }

    @Test func `a refresh token the server did rotate is the one stored`() async throws {
        try world.file.saveAgy(world.expired)
        _ = try await world.access(SequencedTransport([.json(200, AgyAccessWorld.rotated)])).session(now: 5_000)
        #expect(try world.file.loadAgy()?.refreshToken == "rt-2")
    }

    @Test func `a refused grant is reported, leaves the record as it was, and looks for no secret`() async throws {
        try world.file.saveAgy(world.expired)
        let transport = SequencedTransport([.json(400, #"{"error":"invalid_grant"}"#)])
        let found = CallCounter()
        await #expect(throws: AgyAccessError.refreshFailed(.tokenEndpoint(status: 400, code: "invalid_grant"))) {
            _ =
                try await world.access(
                    transport,
                    secret: {
                        found.bump()
                        return "x"
                    }
                )
                .session(now: 5_000)
        }
        #expect(try world.file.loadAgy() == world.expired)
        #expect(found.count == 0 && transport.sent.count == 1)
    }

    @Test func `a transport failure is unreachable, not a refused sign-in`() async throws {
        try world.file.saveAgy(world.expired)
        struct Down: Error {}
        do { _ = try await world.access(SequencedTransport([.failure(Down())])).session(now: 5_000) } catch {
            guard case .unreachable = error else {
                Issue.record("expected unreachable, got \(error)")
                return
            }
            #expect(try world.file.loadAgy() == world.expired)
            return
        }
        Issue.record("a failed transport was not reported")
    }

    @Test func `a token that has not expired is not refreshed even when the project is unknown`() async throws {
        var noProject = world.valid
        noProject.projectID = nil
        try world.file.saveAgy(noProject)
        let transport = SequencedTransport([.json(200, AgyAccessWorld.onboarding)])
        let session = try await world.access(transport).session(now: 5_000)
        #expect(session == AgySession(accessToken: "at-ok", projectID: "proj-1"))
        let sent = try #require(transport.sent.first)
        #expect(transport.sent.count == 1 && sent.url.absoluteString.hasSuffix("loadCodeAssist"))
        #expect(sent.headers.contains { $0.name == "authorization" && $0.value == "Bearer at-ok" })
        let stored = try #require(try world.file.loadAgy())
        #expect(stored.projectID == "proj-1" && stored.tierID == "free-tier" && stored.accessToken == "at-ok")
    }

    @Test func `a refresh and an onboarding in one call both end up stored`() async throws {
        var noProject = world.expired
        noProject.projectID = nil
        noProject.tierID = nil
        try world.file.saveAgy(noProject)
        let transport = SequencedTransport([.json(200, AgyAccessWorld.refreshed), .json(200, AgyAccessWorld.onboarding)]
        )
        let session = try await world.access(transport).session(now: 5_000)
        #expect(session == AgySession(accessToken: "at-2", projectID: "proj-1"))
        let onboarding = try #require(transport.sent.dropFirst().first)
        #expect(
            onboarding.headers.contains { $0.name == "authorization" && $0.value == "Bearer at-2" },
            "onboarded with the new token")
        let stored = try #require(try world.file.loadAgy())
        #expect(stored.accessToken == "at-2" && stored.projectID == "proj-1" && stored.refreshToken == "rt-1")
        let again = SequencedTransport([.json(500, "")])
        #expect(try await world.access(again).session(now: 5_000) == session)
        #expect(again.sent.isEmpty, "the next call sends nothing")
    }

    @Test func `an account with no project is reported, and the record is not changed`() async throws {
        var noProject = world.valid
        noProject.projectID = nil
        try world.file.saveAgy(noProject)
        let transport = SequencedTransport([.json(200, #"{"ineligibleTiers":[{"reasonCode":"UNSUPPORTED_LOCATION"}]}"#)]
        )
        await #expect(throws: AgyAccessError.onboarding(.noProject(reasons: ["UNSUPPORTED_LOCATION"]))) {
            _ = try await world.access(transport).session(now: 5_000)
        }
        #expect(try world.file.loadAgy() == noProject)
    }

    @Test func `a token is expired at its expiry, not after it`() async throws {
        try world.file.saveAgy(world.valid)
        let transport = SequencedTransport([.json(200, AgyAccessWorld.refreshed)])
        _ = try await world.access(transport).session(now: world.valid.expiresAt)
        #expect(transport.sent.count == 1)
        let before = SequencedTransport([.json(500, "")])
        _ = try await world.access(before).session(now: world.valid.expiresAt - 1)
        #expect(before.sent.isEmpty)
    }

    @Test func `an onboarding that cannot reach Google is unreachable, and the record is not changed`() async throws {
        var noProject = world.valid
        noProject.projectID = nil
        try world.file.saveAgy(noProject)
        struct Down: Error {}
        do { _ = try await world.access(SequencedTransport([.failure(Down())])).session(now: 5_000) } catch {
            guard case .unreachable = error else {
                Issue.record("expected unreachable, got \(error)")
                return
            }
            #expect(try world.file.loadAgy() == noProject)
            return
        }
        Issue.record("a failed transport was not reported")
    }
}
