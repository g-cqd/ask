internal import Foundation
internal import Testing

@testable import AskAI

/// Using stored Codex credentials: returned as they are while they last, refreshed when they do not, and saved whole.
///
/// The refresh token is single use. Two ask processes that both see expired credentials must not both refresh: the second
/// would present a token the server has spent, and be refused, perhaps with the sign-in revoked. A lock around "read,
/// refresh, save", and a second look after taking it, makes one refresh serve both.
@Suite("Stored Codex credentials are refreshed once, whole, under a lock shared by every ask process")
struct CodexAccessTests {
    private let file = CredentialFile(
        url: FileManager.default.temporaryDirectory.appending(
            path: "ask-access-\(UUID().uuidString)/ask/credentials.json"))
    private static let claims = #"{"https://api.openai.com/auth":{"chatgpt_account_id":"acct_a"}}"#
    private static let freshAccess = [
        Base64URL.encode(Array(#"{"alg":"none"}"#.utf8)), Base64URL.encode(Array(claims.utf8)), "fresh"
    ]
    .joined(separator: ".")
    private static let tokens = #"{"access_token":"\#(freshAccess)","refresh_token":"rt-2","expires_in":3600}"#
    private let expired = CodexCredentials(
        accessToken: "old", refreshToken: "rt-1", expiresAt: 100, accountID: "acct_a")
    private let valid = CodexCredentials(
        accessToken: "still-good", refreshToken: "rt-1", expiresAt: 10_000, accountID: "acct_a")

    private func access(_ transport: SequencedTransport, lockWait: Duration = .seconds(5)) -> CodexAccess {
        CodexAccess(file: file, client: CodexAuthClient(transport: transport), lockWait: lockWait)
    }

    @Test func `credentials that have not expired are returned without a request`() async throws {
        try file.saveCodex(valid)
        let transport = SequencedTransport([.json(500, "no")])
        #expect(try await access(transport).credentials(now: 5_000) == valid)
        #expect(transport.sent.isEmpty)
    }

    @Test func `expired credentials are refreshed, and the whole new pair is stored`() async throws {
        try file.saveCodex(expired)
        let transport = SequencedTransport([.json(200, Self.tokens)])
        let fresh = try await access(transport).credentials(now: 5_000)
        #expect(fresh.accessToken == Self.freshAccess)
        #expect(fresh.refreshToken == "rt-2")
        #expect(try file.loadCodex() == fresh, "the replacement is saved whole, so the next process uses it")
        #expect(transport.sent.count == 1)
    }

    @Test func `nothing stored is signed out`() async {
        await #expect(throws: CodexAccessError.signedOut) {
            _ = try await access(SequencedTransport([.json(500, "")])).credentials(now: 1)
        }
    }

    @Test func `a refused refresh is reported and leaves what was stored untouched`() async throws {
        try file.saveCodex(expired)
        let transport = SequencedTransport([.json(400, #"{"error":"invalid_grant"}"#)])
        await #expect(throws: CodexAccessError.refreshFailed(.tokenEndpoint(status: 400, code: "invalid_grant"))) {
            _ = try await access(transport).credentials(now: 5_000)
        }
        #expect(try file.loadCodex() == expired)
        #expect(transport.sent.count == 1, "a spent refresh token is never offered again")
    }

    @Test func `two processes that both find the credentials expired refresh once between them`() async throws {
        try file.saveCodex(expired)
        // A second refresh would present the spent token and be refused.
        let transport = SequencedTransport([.json(200, Self.tokens), .json(400, #"{"error":"refresh_token_reused"}"#)])
        let (first, second) = (access(transport), access(transport))
        async let one = first.credentials(now: 5_000)
        async let two = second.credentials(now: 5_000)
        let (a, b) = try await (one, two)
        #expect(a == b)
        #expect(a.refreshToken == "rt-2")
        #expect(transport.sent.count == 1, "the second process must find the first's refresh and use it")
    }

    @Test func `a lock another process holds is waited for, then reported rather than waited on forever`() async throws
    {
        try file.saveCodex(expired)
        let held = try await CredentialLock.acquire(beside: file.url, wait: .seconds(1))
        defer { held.release() }
        let transport = SequencedTransport([.json(200, Self.tokens)])
        await #expect(throws: CodexAccessError.lockUnavailable) {
            _ = try await access(transport, lockWait: .milliseconds(300)).credentials(now: 5_000)
        }
        #expect(transport.sent.isEmpty)
    }

    @Test func `a lock released in time is taken, and the refresh goes ahead`() async throws {
        try file.saveCodex(expired)
        let held = try await CredentialLock.acquire(beside: file.url, wait: .seconds(1))
        Task {
            try? await Task.sleep(for: .milliseconds(200))
            held.release()
        }
        let transport = SequencedTransport([.json(200, Self.tokens)])
        #expect(try await access(transport, lockWait: .seconds(3)).credentials(now: 5_000).refreshToken == "rt-2")
    }

    @Test func `a damaged credential file is reported, never read as signed out`() async throws {
        try file.saveCodex(valid)
        try Data("{not json".utf8).write(to: file.url)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.url.path)
        await #expect(throws: CodexAccessError.storage(.damaged(path: file.url.path))) {
            _ = try await access(SequencedTransport([.json(500, "")])).credentials(now: 1)
        }
    }
}
