internal import Foundation
internal import Testing

@testable import AskAI

/// What Antigravity access does when things go wrong: a secret Google no longer accepts, a record changed or unsaveable meanwhile.
struct AgyAccessRecoveryTests {
    private let world = AgyAccessWorld()
    private static let invalidClient = #"{"error":"invalid_client"}"#

    @Test func `a secret Google refuses is looked for once, tried once, and stored when it works`() async throws {
        try world.file.saveAgy(world.expired)
        let transport = SequencedTransport([.json(401, Self.invalidClient), .json(200, AgyAccessWorld.refreshed)])
        let found = CallCounter()
        let session =
            try await world.access(
                transport,
                secret: {
                    found.bump()
                    return "secret-2"
                }
            )
            .session(now: 5_000)
        #expect(session.accessToken == "at-2" && found.count == 1 && transport.sent.count == 2)
        #expect(world.body(transport.sent[1]).contains("client_secret=secret-2"))
        #expect(try world.file.loadAgy()?.clientSecret == "secret-2")
    }

    @Test func `a second refusal is reported, the secret is not looked for again, and the record keeps its secret`()
        async throws
    {
        try world.file.saveAgy(world.expired)
        let transport = SequencedTransport([.json(401, Self.invalidClient)])
        let found = CallCounter()
        await #expect(throws: AgyAccessError.refreshFailed(.tokenEndpoint(status: 401, code: "invalid_client"))) {
            _ =
                try await world.access(
                    transport,
                    secret: {
                        found.bump()
                        return "secret-2"
                    }
                )
                .session(now: 5_000)
        }
        #expect(found.count == 1 && transport.sent.count == 2)
        #expect(try world.file.loadAgy() == world.expired)
    }

    @Test func `a secret that cannot be found is reported, and nothing more is sent`() async throws {
        try world.file.saveAgy(world.expired)
        let transport = SequencedTransport([.json(401, Self.invalidClient)])
        struct NoAgy: Error, CustomStringConvertible { var description: String { "agy is not installed" } }
        await #expect(throws: AgyAccessError.secretUnavailable("agy is not installed")) {
            _ = try await world.access(transport, secret: { throw NoAgy() }).session(now: 5_000)
        }
        #expect(transport.sent.count == 1)
        #expect(try world.file.loadAgy() == world.expired)
    }

    @Test func `a record with no secret looks for one before it asks Google anything`() async throws {
        var bare = world.expired
        bare.clientSecret = nil
        try world.file.saveAgy(bare)
        let transport = SequencedTransport([.json(200, AgyAccessWorld.refreshed)])
        let found = CallCounter()
        _ =
            try await world.access(
                transport,
                secret: {
                    found.bump()
                    return "secret-9"
                }
            )
            .session(now: 5_000)
        #expect(found.count == 1 && transport.sent.count == 1)
        #expect(world.body(transport.sent[0]).contains("client_secret=secret-9"))
        #expect(try world.file.loadAgy()?.clientSecret == "secret-9")
    }

    // MARK: - A record that changes while a refresh is on its way

    private func refreshing(whileThe change: @escaping @Sendable () -> Void) throws -> (AgyAccess, HookedTransport) {
        try world.file.saveAgy(world.expired)
        let transport = HookedTransport(SequencedTransport([.json(200, AgyAccessWorld.refreshed)]), before: change)
        return (world.access(transport), transport)
    }

    @Test func `a sign-in made meanwhile stands, and is used if it is current`() async throws {
        let file = world.file
        let theirs = AgyCredentials(
            accessToken: "theirs", refreshToken: "rt-9", expiresAt: 10_000, projectID: "p9", clientSecret: "s9")
        let (access, _) = try refreshing { try? file.saveAgy(theirs) }
        #expect(try await access.session(now: 5_000) == AgySession(accessToken: "theirs", projectID: "p9"))
        #expect(try file.loadAgy() == theirs)
    }

    @Test func `a sign-out made meanwhile stands`() async throws {
        let file = world.file
        let (access, _) = try refreshing { try? file.removeAgy() }
        await #expect(throws: AgyAccessError.signedOut) { _ = try await access.session(now: 5_000) }
        #expect(try file.loadAgy() == nil)
    }

    @Test func `a replacement that itself needs refreshing is reported, not refreshed in the same breath`() async throws
    {
        let file = world.file
        let other = AgyCredentials(
            accessToken: "other", refreshToken: "rt-9", expiresAt: 200, projectID: "p9", clientSecret: "s9")
        let (access, _) = try refreshing { try? file.saveAgy(other) }
        await #expect(throws: AgyAccessError.changedDuringRefresh) { _ = try await access.session(now: 5_000) }
        #expect(try file.loadAgy() == other)
    }

    // MARK: - A save that cannot happen

    @Test func `a refresh whose save fails serves its request, keeps the result, and saves it on the next call`()
        async throws
    {
        try world.file.saveAgy(world.expired)
        let transport = SequencedTransport([
            .json(200, AgyAccessWorld.rotated), .json(400, #"{"error":"invalid_grant"}"#)
        ])
        let access = world.access(transport)
        let held = try CredentialLock.acquireBlocking(beside: world.file.url, wait: .seconds(1), name: "write")
        let first = try await access.session(now: 5_000)
        #expect(first.accessToken == "at-2" && access.rotationIsUnsaved)
        #expect(access.unsavedReason?.isEmpty == false, "there is a reason to tell the person")
        #expect(try world.file.loadAgy() == world.expired, "the file still holds the old record")
        held.release()
        #expect(try await access.session(now: 5_000) == first)
        #expect(transport.sent.count == 1, "the old token was never offered again")
        #expect(try world.file.loadAgy()?.refreshToken == "rt-2" && !access.rotationIsUnsaved)
        #expect(access.unsavedReason == nil)
    }

    @Test func `a secret found a moment ago is not looked for again when Google refuses it too`() async throws {
        var bare = world.expired
        bare.clientSecret = nil
        try world.file.saveAgy(bare)
        let transport = SequencedTransport([.json(401, Self.invalidClient)])
        let found = CallCounter()
        await #expect(throws: AgyAccessError.refreshFailed(.tokenEndpoint(status: 401, code: "invalid_client"))) {
            _ =
                try await world.access(
                    transport,
                    secret: {
                        found.bump()
                        return "secret-9"
                    }
                )
                .session(now: 5_000)
        }
        #expect(found.count == 1 && transport.sent.count == 1)
    }

    @Test func `while a save keeps failing, a later refresh starts from what is held and is saved once it can be`()
        async throws
    {
        try world.file.saveAgy(world.expired)
        let third = #"{"access_token":"at-3","refresh_token":"rt-3","expires_in":3599,"token_type":"Bearer"}"#
        let transport = SequencedTransport([.json(200, AgyAccessWorld.rotated), .json(200, third)])
        let access = world.access(transport)
        let held = try CredentialLock.acquireBlocking(beside: world.file.url, wait: .seconds(1), name: "write")
        _ = try await access.session(now: 5_000)
        let later = try await access.session(now: 100_000)
        #expect(later.accessToken == "at-3" && access.rotationIsUnsaved)
        #expect(
            world.body(transport.sent[1]).contains("refresh_token=rt-2"),
            "refreshed from the rotated token, not the spent one")
        #expect(try world.file.loadAgy() == world.expired, "the file has still taken nothing")
        held.release()
        _ = try await access.session(now: 100_000)
        #expect(
            try world.file.loadAgy()?.refreshToken == "rt-3",
            "what the file held was replaced by the latest, not by the first")
        #expect(!access.rotationIsUnsaved && transport.sent.count == 2)
    }

    @Test func `an onboarding while the save is blocked is kept in memory, and both are saved on the next call`()
        async throws
    {
        var noProject = world.expired
        noProject.projectID = nil
        try world.file.saveAgy(noProject)
        let transport = SequencedTransport([.json(200, AgyAccessWorld.rotated), .json(200, AgyAccessWorld.onboarding)])
        let access = world.access(transport)
        let held = try CredentialLock.acquireBlocking(beside: world.file.url, wait: .seconds(1), name: "write")
        let first = try await access.session(now: 5_000)
        #expect(first == AgySession(accessToken: "at-2", projectID: "proj-1") && access.rotationIsUnsaved)
        held.release()
        #expect(try await access.session(now: 5_000) == first)
        let stored = try #require(try world.file.loadAgy())
        #expect(stored.refreshToken == "rt-2" && stored.projectID == "proj-1" && !access.rotationIsUnsaved)
        #expect(transport.sent.count == 2)
    }
}
