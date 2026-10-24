internal import Foundation
internal import Testing

@testable import AskAI

/// Claude's refresh token is single use (probed live on a disposable named connection, diary 2026-10-24-22): a refresh rotates
/// it, the spent one is refused with HTTP 400 `invalid_grant`, and of two refreshes of one token sent at once exactly one succeeds.
/// So two asks that both find the credentials expired must refresh once between them, under a lock, as Codex's do (ADR-0036).
struct ClaudeRefreshLockTests {
    private let file = CredentialFile(
        url: FileManager.default.temporaryDirectory.appending(
            path: "ask-claude-lock-\(UUID().uuidString)/ask/credentials.json"))

    private static let refreshed =
        #"{"token_type":"bearer","access_token":"sk-ant-oat-NEW","refresh_token":"sk-ant-ort-NEW","expires_in":3600,"scope":"user:inference"}"#
    private static let spent = #"{"error":"invalid_grant","error_description":"Refresh token not found or invalid"}"#

    private func expire(email: String? = "a@b.example") throws {
        try file.saveClaude(
            ClaudeCredentials(
                accessToken: "sk-ant-oat-OLD", refreshToken: "sk-ant-ort-OLD", expiresAt: 100, refreshExpiresAt: nil,
                accountEmail: email, organizationName: nil, scopes: "user:inference"))
    }

    private func access(
        _ transport: SequencedTransport, lockWait: Duration = .seconds(5), connection: ConnectionRecord? = nil,
        file override: CredentialFile? = nil
    ) -> ClaudeAccess {
        ClaudeAccess(
            file: override ?? file, client: ClaudeAuthClient(transport: transport), lockWait: lockWait,
            connection: connection)
    }

    @Test func `two processes that both find the credentials expired refresh once between them`() async throws {
        try expire()
        let transport = SequencedTransport([.json(200, Self.refreshed), .json(400, Self.spent)])
        let (first, second) = (access(transport), access(transport))
        async let one = first.auth(now: 5_000)
        async let two = second.auth(now: 5_000)
        let (a, b) = try await (one, two)
        #expect(a == b && a == .subscription(accessToken: "sk-ant-oat-NEW"))
        #expect(
            transport.sent.count == 1,
            "the second process must find the first's refresh and use it, not offer a spent token")
        #expect(try file.loadClaude()?.refreshToken == "sk-ant-ort-NEW")
    }

    @Test func `a lock another process holds is waited for, then reported rather than waited on forever`() async throws
    {
        try expire()
        let held = try await CredentialLock.acquire(beside: file.url, wait: .seconds(1), name: ClaudeAccess.lockName)
        defer { held.release() }
        let transport = SequencedTransport([.json(200, Self.refreshed)])
        await #expect(throws: ClaudeAccessError.lockUnavailable) {
            _ = try await access(transport, lockWait: .milliseconds(300)).auth(now: 5_000)
        }
        #expect(transport.sent.isEmpty)
        #expect(try file.loadClaude()?.refreshToken == "sk-ant-ort-OLD")
    }

    @Test func `a lock released by its holder is taken, and the refresh goes ahead`() async throws {
        try expire()
        let held = try await CredentialLock.acquire(beside: file.url, wait: .seconds(1), name: ClaudeAccess.lockName)
        Task { held.release() }
        let transport = SequencedTransport([.json(200, Self.refreshed)])
        #expect(
            try await access(transport, lockWait: .seconds(3)).auth(now: 5_000)
                == .subscription(accessToken: "sk-ant-oat-NEW"))
    }

    @Test func `a Codex refresh in progress does not block Claude's, since they are different grants`() async throws {
        try expire()
        let codex = try await CredentialLock.acquire(beside: file.url, wait: .seconds(1))
        defer { codex.release() }
        let transport = SequencedTransport([.json(200, Self.refreshed)])
        #expect(
            try await access(transport, lockWait: .milliseconds(300)).auth(now: 5_000)
                == .subscription(accessToken: "sk-ant-oat-NEW"))
    }

    @Test func `credentials that were refreshed while this process waited are used without a request`() async throws {
        try expire()
        let held = try await CredentialLock.acquire(beside: file.url, wait: .seconds(1), name: ClaudeAccess.lockName)
        let transport = SequencedTransport([.json(400, Self.spent)])
        let waiting = Task { try await access(transport, lockWait: .seconds(5)).auth(now: 5_000) }
        // Another process finished its refresh and released the lock.
        try file.saveClaude(
            ClaudeCredentials(
                accessToken: "sk-ant-oat-OTHER", refreshToken: "sk-ant-ort-OTHER", expiresAt: 90_000,
                refreshExpiresAt: nil,
                accountEmail: "a@b.example", organizationName: nil, scopes: "user:inference"))
        held.release()
        #expect(try await waiting.value == .subscription(accessToken: "sk-ant-oat-OTHER"))
        #expect(transport.sent.isEmpty, "the stored credentials were fresh once the lock was taken")
    }

    @Test func `a refused refresh is reported, leaves what was stored, and is never retried`() async throws {
        try expire()
        let transport = SequencedTransport([.json(400, Self.spent), .json(200, Self.refreshed)])
        await #expect(throws: ClaudeAccessError.refreshFailed(.tokenEndpoint(status: 400, code: "invalid_grant"))) {
            _ = try await access(transport).auth(now: 5_000)
        }
        #expect(try file.loadClaude()?.refreshToken == "sk-ant-ort-OLD")
        #expect(transport.sent.count == 1)
    }

    private func named() throws -> (ConnectionRecord, CredentialFile) {
        let root = FileManager.default.temporaryDirectory.appending(path: "ask-claude-named-\(UUID().uuidString)")
        let registry = ConnectionRegistry(directory: root)
        let record = try registry.register(name: "claude-a", provider: .anthropic)
        return (record, registry.credentials(for: record))
    }

    private func nameThe(account email: String) -> String {
        #"{"token_type":"bearer","access_token":"sk-ant-oat-NEW","refresh_token":"sk-ant-ort-NEW","expires_in":3600,"scope":"user:inference","account":{"email_address":"\#(email)"}}"#
    }

    @Test func `a named connection whose refresh names another account is refused and keeps what was stored`()
        async throws
    {
        let (record, credentials) = try named()
        let stored = ClaudeCredentials(
            accessToken: "sk-ant-oat-OLD", refreshToken: "sk-ant-ort-OLD", expiresAt: 100, refreshExpiresAt: nil,
            accountEmail: "mine@example.com", organizationName: nil, scopes: "user:inference")
        try credentials.saveClaude(stored)
        let transport = SequencedTransport([.json(200, nameThe(account: "someone-else@example.com"))])
        await #expect(throws: ClaudeAccessError.accountChanged) {
            _ = try await access(transport, connection: record, file: credentials).auth(now: 5_000)
        }
        #expect(try credentials.loadClaude(connection: record) == stored)
    }

    @Test func `a named connection whose refresh names the same account is refreshed`() async throws {
        let (record, credentials) = try named()
        try credentials.saveClaude(
            ClaudeCredentials(
                accessToken: "sk-ant-oat-OLD", refreshToken: "sk-ant-ort-OLD", expiresAt: 100, refreshExpiresAt: nil,
                accountEmail: "mine@example.com", organizationName: nil, scopes: "user:inference"))
        let transport = SequencedTransport([.json(200, nameThe(account: "mine@example.com"))])
        let auth = try await access(transport, connection: record, file: credentials).auth(now: 5_000)
        #expect(auth == .subscription(accessToken: "sk-ant-oat-NEW"))
    }

    @Test func `the default sign-in is not held to an account, since it never recorded one it must keep`() async throws
    {
        try expire(email: "old@example.com")
        let transport = SequencedTransport([.json(200, nameThe(account: "new@example.com"))])
        #expect(try await access(transport).auth(now: 5_000) == .subscription(accessToken: "sk-ant-oat-NEW"))
    }

    @Test func `every failure reads as a sentence that names what to do and carries nothing secret`() {
        let all: [ClaudeAccessError] = [
            .signedOut, .lockUnavailable, .changedDuringRefresh, .accountChanged,
            .refreshFailed(.tokenEndpoint(status: 400, code: "invalid_grant")),
            .storage(.damaged(path: "/x/credentials.json"))
        ]
        #expect(all.allSatisfy { !$0.description.isEmpty && !$0.description.contains("sk-ant") })
        #expect(ClaudeAccessError.signedOut.description.contains("ask login"))
        #expect(
            ClaudeAccessError.refreshFailed(.tokenEndpoint(status: 400, code: "invalid_grant")).description
                .contains("ask login"))
    }
}
