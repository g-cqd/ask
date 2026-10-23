internal import Foundation
internal import Testing

@testable import AskAI

/// A candidate is the secret only when Google's token endpoint says so: HTTP 400 `invalid_grant` for the Antigravity client id
/// presented with a code that cannot be real. The error code is the signal, not the status (`invalid_client` is a 401).
struct AgyClientSecretVerifierTests {
    private static let wrong = #"{"error":"invalid_client","error_description":"Unauthorized"}"#
    private static let right = #"{"error":"invalid_grant","error_description":"Malformed auth code."}"#

    private func candidates(_ count: Int) -> [String] {
        (0 ..< count).map { "GOCSPX-" + String(format: "%028d", $0) }
    }

    @Test func `the first pairing Google accepts is returned and the search stops`() async throws {
        let transport = SequencedTransport([.json(401, Self.wrong), .json(400, Self.right), .json(401, Self.wrong)])
        let found = try await AgyClientSecret.verified(candidates(3), transport: transport)
        #expect(found == candidates(3)[1])
        #expect(transport.sent.count == 2)
    }

    @Test func `each probe presents the Antigravity client, the candidate and a code that cannot be real, over TLS`()
        async throws
    {
        let transport = SequencedTransport([.json(400, Self.right)])
        _ = try await AgyClientSecret.verified(candidates(1), transport: transport)
        let request = try #require(transport.sent.first)
        #expect(request.url.absoluteString == "https://oauth2.googleapis.com/token" && request.method == "POST")
        let body = request.bodyText
        #expect(body.contains("client_id=\(AgyOAuth.clientID)") && body.contains("client_secret=\(candidates(1)[0])"))
        #expect(body.contains("grant_type=authorization_code") && body.contains("code=not-a-real-code"))
        #expect(!body.contains("refresh_token") && !body.contains("code_verifier"))
    }

    @Test func `when no candidate pairs the answer is nil, not an error`() async throws {
        let transport = SequencedTransport([.json(401, Self.wrong)])
        let found = try await AgyClientSecret.verified(candidates(3), transport: transport)
        #expect(found == nil)
        #expect(transport.sent.count == 3)
    }

    @Test func `no candidates means no request`() async throws {
        let transport = SequencedTransport([.json(400, Self.right)])
        #expect(try await AgyClientSecret.verified([], transport: transport) == nil)
        #expect(transport.sent.isEmpty)
    }

    @Test(arguments: [
        (500, #"{"error":"backend_error"}"#), (429, "slow down"), (200, "{}"), (400, "<html>"),
        (403, #"{"error":"access_denied"}"#),
        (400, #"{"error":"invalid_request"}"#)
    ])
    func `an answer that is neither pairing nor rejection stops the search instead of guessing on`(
        _ status: Int, _ body: String
    ) async {
        let transport = SequencedTransport([.json(status, body), .json(400, Self.right)])
        await #expect(throws: AgySecretError.inconclusive(status: status)) {
            try await AgyClientSecret.verified(candidates(2), transport: transport)
        }
        #expect(transport.sent.count == 1)
    }

    @Test func `a flood of candidates costs a bounded number of requests`() async throws {
        let transport = SequencedTransport([.json(401, Self.wrong)])
        let found = try await AgyClientSecret.verified(candidates(40), transport: transport)
        #expect(found == nil)
        #expect(transport.sent.count == AgyClientSecret.attemptLimit)
    }

    @Test func `a transport failure is reported as such, and no message carries a candidate`() async {
        struct Down: Error {}
        let transport = SequencedTransport([.failure(Down())])
        do {
            _ = try await AgyClientSecret.verified(candidates(1), transport: transport)
            Issue.record("expected a failure")
        } catch {
            #expect(!String(describing: error).contains("GOCSPX"))
        }
    }

    @Test func `no description of any failure contains a candidate`() {
        let all: [AgySecretError] = [
            .binaryNotFound, .unreadable(path: "/x/agy"), .noCandidates, .notVerified, .inconclusive(status: 500)
        ]
        #expect(all.allSatisfy { !$0.description.contains("GOCSPX") && !$0.description.isEmpty })
    }
}
