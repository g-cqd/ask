internal import Foundation
internal import Testing

@testable import AskAI

/// Codex's device-code sign-in, for a machine with no browser to redirect back to: a code to type at a link, polling
/// at the server's pace, then an exchange. Shapes and rules are those pi-integrations' working implementation pins.
@Suite("Codex's device-code sign-in shows a code, polls at the server's pace and exchanges for credentials")
struct CodexDeviceSignInTests {
    private static let started = #"{"device_auth_id":"dev-1","user_code":"ABCD-1234","interval":"5"}"#
    private static let granted = #"{"authorization_code":"auth-code-xyz","code_verifier":"server-verifier"}"#
    private static let access: String = {
        let claims = #"{"https://api.openai.com/auth":{"chatgpt_account_id":"acct_7"}}"#
        return [Base64URL.encode(Array(#"{"alg":"none"}"#.utf8)), Base64URL.encode(Array(claims.utf8)), "sig"]
            .joined(separator: ".")
    }()
    private static var tokens: String { #"{"access_token":"\#(access)","refresh_token":"rt-1","expires_in":3600}"# }

    private func run(_ replies: [SequencedTransport.Reply], clock: StepClock = StepClock()) async throws -> (
        credentials: CodexCredentials, transport: SequencedTransport, prompts: [SignInPrompt], clock: StepClock
    ) {
        let transport = SequencedTransport(replies)
        let prompts = PromptLog()
        let flow = CodexDeviceSignIn(transport: transport, now: { 100 })
        let credentials = try await SignInRunner(clock: clock).run(flow) { prompts.add($0) }
        return (credentials, transport, prompts.all, clock)
    }

    @Test func `a full sign-in shows the code, waits the server's interval, and exchanges for credentials`()
        async throws
    {
        let done = try await run([
            .json(200, Self.started), .json(403, "{}"), .json(200, Self.granted), .json(200, Self.tokens)
        ])
        #expect(done.credentials.accountID == "acct_7")
        #expect(done.credentials.refreshToken == "rt-1")
        #expect(done.prompts.map(\.url.absoluteString) == ["https://auth.openai.com/codex/device"])
        #expect(done.prompts.first?.instructions?.contains("ABCD-1234") == true)
        #expect(done.clock.sleeps == [.seconds(5), .seconds(5)], "the first poll waits an interval too")
        let sent = done.transport.sent
        #expect(
            sent.map(\.url.absoluteString) == [
                "https://auth.openai.com/api/accounts/deviceauth/usercode",
                "https://auth.openai.com/api/accounts/deviceauth/token",
                "https://auth.openai.com/api/accounts/deviceauth/token",
                "https://auth.openai.com/oauth/token"
            ])
        #expect(sent[0].bodyText == #"{"client_id":"app_EMoamEEZ73f0CkXaXp7hrann"}"#)
        #expect(sent[1].bodyText == #"{"device_auth_id":"dev-1","user_code":"ABCD-1234"}"#)
        #expect(sent[3].bodyText.contains("code=auth-code-xyz"))
        #expect(sent[3].bodyText.contains("code_verifier=server-verifier"))
        #expect(sent[3].bodyText.contains("redirect_uri=https%3A%2F%2Fauth.openai.com%2Fdeviceauth%2Fcallback"))
    }

    @Test(arguments: [("\"7\"", 7), ("7", 7), ("0", 1), ("500", 60), ("\" 9 \"", 9)])
    func `the server's interval is read as text or number and kept between one and sixty seconds`(
        raw: String, seconds: Int
    ) async throws {
        let body = #"{"device_auth_id":"d","user_code":"ABC-123","interval":\#(raw)}"#
        let done = try await run([.json(200, body), .json(200, Self.granted), .json(200, Self.tokens)])
        #expect(done.clock.sleeps == [.seconds(seconds)])
    }

    @Test func `a slow down makes every later wait five seconds longer`() async throws {
        let done = try await run([
            .json(200, Self.started), .json(400, #"{"error":"slow_down"}"#),
            .json(400, #"{"error":{"code":"deviceauth_authorization_pending"}}"#), .json(200, Self.granted),
            .json(200, Self.tokens)
        ])
        #expect(done.clock.sleeps == [.seconds(5), .seconds(10), .seconds(10)])
    }

    @Test(arguments: [403, 404])
    func `not approved yet is 403 or 404, and is not an error`(status: Int) async throws {
        let done = try await run([
            .json(200, Self.started), .json(status, "{}"), .json(200, Self.granted), .json(200, Self.tokens)
        ])
        #expect(done.credentials.accountID == "acct_7")
    }

    @Test func `a server without device sign-in says so, rather than failing mysteriously`() async {
        await #expect(throws: SignInError.rejected(status: 404)) { _ = try await run([.json(404, "{}")]) }
    }

    @Test(arguments: [
        #"{"device_auth_id":"has space","user_code":"ABC-123","interval":5}"#,
        #"{"device_auth_id":"d","user_code":"no spaces allowed","interval":5}"#,
        #"{"device_auth_id":"d","user_code":"AB","interval":5}"#, #"{"device_auth_id":"d","user_code":"ABC-123"}"#,
        #"{"device_auth_id":"d","user_code":"ABC-123","interval":-1}"#, #"{"user_code":"ABC-123","interval":5}"#,
        "not json"
    ])
    func `a device response that is not plainly a device response is refused before any poll`(body: String) async {
        let transport = SequencedTransport([.json(200, body), .json(200, Self.granted)])
        let flow = CodexDeviceSignIn(transport: transport, now: { 0 })
        await #expect(throws: SignInError.self) { _ = try await SignInRunner(clock: StepClock()).run(flow) { _ in } }
        #expect(transport.sent.count == 1)
    }

    @Test func `any other refusal while polling ends the sign-in`() async {
        await #expect(throws: SignInError.rejected(status: 500)) {
            _ = try await run([.json(200, Self.started), .json(500, "oops")])
        }
    }

    @Test(arguments: [
        #"{"authorization_code":"a"}"#, #"{"code_verifier":"v"}"#, #"{"authorization_code":"a b","code_verifier":"v"}"#,
        "{}"
    ])
    func `a grant missing either value, or with an unsafe one, is refused`(body: String) async {
        await #expect(throws: SignInError.invalidResponse("grant")) {
            _ = try await run([.json(200, Self.started), .json(200, body)])
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func `a sign-in nobody approves times out after fifteen minutes`() async {
        let clock = StepClock()
        await #expect(throws: SignInError.timedOut) {
            _ = try await run([.json(200, Self.started), .json(403, "{}")], clock: clock)
        }
        #expect(clock.sleeps.reduce(.zero, +) == .seconds(900))
    }

    @Test func `a refused exchange is reported without repeating the grant`() async {
        do {
            _ = try await run([
                .json(200, Self.started), .json(200, Self.granted), .json(400, #"{"error":"invalid_grant"}"#)
            ])
            Issue.record("signed in")
        } catch {
            #expect(error as? SignInError == .rejected(status: 400))
            #expect(!"\(error)".contains("auth-code-xyz"))
        }
    }
}
