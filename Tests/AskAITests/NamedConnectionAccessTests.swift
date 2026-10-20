internal import Foundation
internal import Testing

@testable import AskAI

struct NamedConnectionAccessTests {
    private func withRegistry(_ body: (ConnectionRegistry) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "ask-two-accounts-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try await body(ConnectionRegistry(directory: root))
    }

    private func expired(_ account: String) -> CodexCredentials {
        CodexCredentials(
            accessToken: "old-" + account, refreshToken: "refresh-" + account, expiresAt: 1, accountID: account)
    }

    private func tokens(_ account: String) -> String {
        let claims = #"{"https://api.openai.com/auth":{"chatgpt_account_id":"\#(account)"}}"#
        let token = Base64URL.encode(Array("{}".utf8)) + "." + Base64URL.encode(Array(claims.utf8)) + ".signature"
        return #"{"access_token":"\#(token)","refresh_token":"new-\#(account)","expires_in":3600}"#
    }

    @Test func `one connection's held refresh lock does not block another connection's refresh`() async throws {
        try await withRegistry { registry in
            let a = try registry.register(name: "personal", provider: .codex)
            let b = try registry.register(name: "work", provider: .codex)
            try registry.saveCodex(expired("account_a"), for: a)
            try registry.saveCodex(expired("account_b"), for: b)
            let held = try await CredentialLock.acquire(beside: registry.credentials(for: a).url, wait: .zero)
            defer { held.release() }
            let transport = SequencedTransport([.json(200, tokens("account_b"))])
            let fresh = try await CodexAccess(
                file: registry.credentials(for: b), client: CodexAuthClient(transport: transport),
                lockWait: .zero, connection: b
            )
            .credentials(now: 100)
            #expect(fresh.accountID == "account_b")
            #expect(fresh.refreshToken == "new-account_b")
            #expect(try registry.credentials(for: a).loadCodex(connection: a) == expired("account_a"))
            #expect(transport.sent.count == 1)
            #expect(transport.sent.first?.bodyText.contains("refresh-account_b") == true)
            #expect(transport.sent.first?.bodyText.contains("refresh-account_a") == false)
        }
    }

    @Test func `a named connection refuses a refreshed grant for a different remote account`() async throws {
        try await withRegistry { registry in
            let record = try registry.register(name: "work", provider: .codex)
            let old = expired("account_a")
            try registry.saveCodex(old, for: record)
            let transport = SequencedTransport([.json(200, tokens("account_b"))])
            await #expect(throws: CodexAccessError.accountChanged) {
                try await CodexAccess(
                    file: registry.credentials(for: record), client: CodexAuthClient(transport: transport),
                    connection: record
                )
                .credentials(now: 100)
            }
            #expect(try registry.credentials(for: record).loadCodex(connection: record) == old)
            #expect(transport.sent.count == 1)
        }
    }

    @Test func `simultaneous registrations of one name allocate only one stable identity`() async throws {
        try await withRegistry { registry in
            let ids = try await withThrowingTaskGroup(of: UUID.self) { group in
                for _ in 0 ..< 8 { group.addTask { try registry.register(name: "work", provider: .codex).id } }
                var ids = Set<UUID>()
                for try await id in group { ids.insert(id) }
                return ids
            }
            #expect(ids.count == 1)
            #expect(try registry.list().records.count == 1)
        }
    }
}
