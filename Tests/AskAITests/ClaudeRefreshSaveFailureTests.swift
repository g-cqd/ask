internal import Foundation
internal import Testing

@testable import AskAI

/// Found by the TLA+ model `docs/formal/CredentialRefresh.tla`: a refresh the server accepted whose save then fails (the save lock held
/// past `lockWait`, a full disk, a failed rename) used to drop the rotated credentials, leaving the single-use token in the file spent
/// (ADR-0074), so a failure that was only transient signed the user out (roadmap 0056, ADR-0082). The rotated pair is now kept in
/// memory, this request goes ahead with it, and every later call tries the save again before anything else.
@Suite("A refresh whose save fails keeps the rotated credentials until they can be saved")
struct ClaudeRefreshSaveFailureTests {
    private let file = CredentialFile(
        url: FileManager.default.temporaryDirectory.appending(
            path: "ask-claude-save-failure-\(UUID().uuidString)/ask/credentials.json"),
        lockWait: .milliseconds(50))

    private static func tokens(_ name: String) -> String {
        #"{"token_type":"bearer","access_token":"sk-ant-oat-\#(name)","refresh_token":"sk-ant-ort-\#(name)","expires_in":3600,"scope":"user:inference"}"#
    }
    private static let spent = #"{"error":"invalid_grant","error_description":"Refresh token not found or invalid"}"#

    private func credentials(_ name: String, expiresAt: Double = 100) -> ClaudeCredentials {
        ClaudeCredentials(
            accessToken: "sk-ant-oat-\(name)", refreshToken: "sk-ant-ort-\(name)", expiresAt: expiresAt,
            refreshExpiresAt: nil, accountEmail: "a@b.example", organizationName: nil, scopes: "user:inference")
    }

    private func holdingTheSaveLock() throws -> CredentialLock {
        try CredentialLock.acquireBlocking(beside: file.url, wait: .seconds(1), name: "write")
    }

    private func token(_ auth: AnthropicClient.Auth) -> String? {
        if case .subscription(let accessToken) = auth { accessToken } else { nil }
    }

    @Test func `the request that rotated the token goes ahead with the new one when its save fails`() async throws {
        try file.saveClaude(credentials("OLD"))
        let transport = SequencedTransport([.json(200, Self.tokens("NEW")), .json(400, Self.spent)])
        let access = ClaudeAccess(file: file, client: ClaudeAuthClient(transport: transport))
        let held = try holdingTheSaveLock()
        defer { held.release() }
        let auth = try await access.auth(now: 5_000)
        #expect(token(auth) == "sk-ant-oat-NEW")
        #expect(access.rotationIsUnsaved)
        #expect(try file.loadClaude()?.refreshToken == "sk-ant-ort-OLD", "the file still holds the spent token")
    }

    @Test func `the next call saves what could not be saved, and does not offer the spent token to the server`()
        async throws
    {
        try file.saveClaude(credentials("OLD"))
        let transport = SequencedTransport([.json(200, Self.tokens("NEW")), .json(400, Self.spent)])
        let access = ClaudeAccess(file: file, client: ClaudeAuthClient(transport: transport))
        let held = try holdingTheSaveLock()
        _ = try await access.auth(now: 5_000)
        held.release()
        let auth = try await access.auth(now: 5_000)
        #expect(token(auth) == "sk-ant-oat-NEW")
        #expect(transport.sent.count == 1, "one refresh, however many calls: the spent token was never offered again")
        #expect(try file.loadClaude()?.refreshToken == "sk-ant-ort-NEW")
        #expect(!access.rotationIsUnsaved)
    }

    @Test func `while the save keeps failing, the next refresh starts from the rotated token, not the stored one`()
        async throws
    {
        try file.saveClaude(credentials("OLD"))
        let transport = SequencedTransport([.json(200, Self.tokens("NEW")), .json(200, Self.tokens("NEWER"))])
        let access = ClaudeAccess(file: file, client: ClaudeAuthClient(transport: transport))
        let held = try holdingTheSaveLock()
        _ = try await access.auth(now: 5_000)
        let later = try await access.auth(now: 100_000)  // the rotated access token has expired too
        #expect(token(later) == "sk-ant-oat-NEWER")
        let second = String(decoding: transport.sent[1].body, as: UTF8.self)
        #expect(second.contains("sk-ant-ort-NEW") && !second.contains("sk-ant-ort-OLD"))
        held.release()
        _ = try await access.auth(now: 100_000)
        #expect(
            try file.loadClaude()?.refreshToken == "sk-ant-ort-NEWER", "the file was brought up to date in one step")
        #expect(!access.rotationIsUnsaved)
    }

    @Test func `a lock that frees up during the second refresh lets that one step bring the file up to date`()
        async throws
    {
        try file.saveClaude(credentials("OLD"))
        let inner = SequencedTransport([.json(200, Self.tokens("NEW")), .json(200, Self.tokens("NEWER"))])
        let held = try holdingTheSaveLock()
        let access = ClaudeAccess(
            file: file, client: ClaudeAuthClient(transport: ReleaseOnSendTransport(inner, releasing: held, at: 2)))
        _ = try await access.auth(now: 5_000)
        #expect(access.rotationIsUnsaved)
        let later = try await access.auth(now: 100_000)
        #expect(token(later) == "sk-ant-oat-NEWER")
        #expect(
            try file.loadClaude()?.refreshToken == "sk-ant-ort-NEWER", "saved over the spent token the file still held")
        #expect(!access.rotationIsUnsaved)
    }

    @Test func `what the user did meanwhile stands: a new sign-in is not overwritten by the held credentials`()
        async throws
    {
        try file.saveClaude(credentials("OLD"))
        let transport = SequencedTransport([.json(200, Self.tokens("NEW")), .json(400, Self.spent)])
        let access = ClaudeAccess(file: file, client: ClaudeAuthClient(transport: transport))
        let held = try holdingTheSaveLock()
        _ = try await access.auth(now: 5_000)
        held.release()
        try file.saveClaude(credentials("FRESH-LOGIN", expiresAt: 1_000_000))
        let auth = try await access.auth(now: 5_000)
        #expect(token(auth) == "sk-ant-oat-FRESH-LOGIN")
        #expect(try file.loadClaude()?.refreshToken == "sk-ant-ort-FRESH-LOGIN")
        #expect(!access.rotationIsUnsaved)
    }

    @Test
    func
        `a second ask process is refused while the first holds a rotation it could not save, and recovers when it does`()
        async throws
    {
        // The limit ADR-0082 does not remove: the held pair lives in the first process's memory, and the file still holds the spent token.
        try file.saveClaude(credentials("OLD"))
        let first = ClaudeAccess(
            file: file, client: ClaudeAuthClient(transport: SequencedTransport([.json(200, Self.tokens("NEW"))])))
        let held = try holdingTheSaveLock()
        _ = try await first.auth(now: 5_000)
        held.release()
        let second = ClaudeAccess(
            file: file, client: ClaudeAuthClient(transport: SequencedTransport([.json(400, Self.spent)])))
        do {
            _ = try await second.auth(now: 5_000)
            Issue.record("the spent token was accepted")
        } catch {
            guard case .refreshFailed = error else {
                Issue.record("expected a refused refresh, got \(error)")
                return
            }
        }
        #expect(try file.loadClaude()?.refreshToken == "sk-ant-ort-OLD", "a refused refresh leaves the file as it was")
        _ = try await first.auth(now: 5_000)  // the first process's next call saves what it held
        let recovered = try await second.auth(now: 5_000)
        #expect(
            token(recovered) == "sk-ant-oat-NEW",
            "and the second process can use what the first saved, with nothing sent")
    }

    @Test func `a refresh that is saved the first time holds nothing back`() async throws {
        try file.saveClaude(credentials("OLD"))
        let transport = SequencedTransport([.json(200, Self.tokens("NEW"))])
        let access = ClaudeAccess(file: file, client: ClaudeAuthClient(transport: transport))
        _ = try await access.auth(now: 5_000)
        #expect(!access.rotationIsUnsaved)
        #expect(try file.loadClaude()?.refreshToken == "sk-ant-ort-NEW")
    }
}
