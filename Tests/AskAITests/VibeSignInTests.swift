import Foundation
import Testing

@testable import AskAI

/// Mistral Vibe's sign-in: a PKCE-bound process, browser approval, polling, and an exchange for an API key. The cases
/// are those pi-integrations' tests pin, because each is an attack a sign-in endpoint's answer could carry.
@Suite("Mistral Vibe's sign-in exchanges an approved process for a key, and trusts no address it is given")
struct VibeSignInTests {
    /// RFC 7636's own example pair.
    private static let pkce = PKCE(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
    private static let challenge = "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"
    /// 2030-01-01T00:00:00Z.
    private static let epoch = 1_893_456_000.0
    private static let completed = #"{"status":"completed","exchange_token":"xchg-token-1"}"#
    private static let pending = #"{"status":"pending"}"#
    private static let exchanged = #"{"api_key":"mistral-key-1"}"#

    private static func begun(_ fields: [String: String] = [:]) -> String {
        let defaults = [
            "process_id": "proc-1", "sign_in_url": "https://console.mistral.ai/vibe/sign-in?process=proc-1",
            "poll_url": "https://console.mistral.ai/api/vibe/sign-in/proc-1", "expires_at": "2030-01-01T00:01:00Z"
        ]
        let merged = defaults.merging(fields) { _, new in new }
        return "{" + merged.sorted { $0.key < $1.key }.map { "\"\($0.key)\":\"\($0.value)\"" }.joined(separator: ",")
            + "}"
    }

    private func flow(_ transport: SequencedTransport) -> VibeSignIn {
        VibeSignIn(transport: transport, pkce: Self.pkce, now: { Self.epoch })
    }

    private func run(_ replies: [SequencedTransport.Reply], clock: StepClock = StepClock()) async throws -> (
        key: StoredKey, transport: SequencedTransport, links: [URL], clock: StepClock
    ) {
        let transport = SequencedTransport(replies)
        let links = LinkLog()
        let key = try await SignInRunner(clock: clock).run(flow(transport)) { links.add($0) }
        return (key, transport, links.all, clock)
    }

    @Test func `a full sign-in binds the start to the exchange by the PKCE pair`() async throws {
        let done = try await run([
            .json(200, Self.begun()), .json(200, Self.pending), .json(200, Self.completed), .json(200, Self.exchanged)
        ])
        #expect(done.key == StoredKey(key: "mistral-key-1", obtainedAt: Self.epoch))
        #expect(done.links.map(\.absoluteString) == ["https://console.mistral.ai/vibe/sign-in?process=proc-1"])
        let sent = done.transport.sent
        #expect(sent.map(\.method) == ["POST", "GET", "GET", "POST"])
        #expect(sent[0].url.absoluteString == "https://console.mistral.ai/api/vibe/sign-in")
        #expect(sent[0].bodyText == #"{"code_challenge":"\#(Self.challenge)","code_challenge_method":"S256"}"#)
        #expect(sent[3].url.absoluteString == "https://console.mistral.ai/api/vibe/sign-in/proc-1/exchange")
        #expect(sent[3].bodyText == #"{"exchange_token":"xchg-token-1","code_verifier":"\#(Self.pkce.verifier)"}"#)
        #expect(done.clock.sleeps == [.seconds(3)])
    }

    @Test(arguments: [
        ["poll_url": "https://untrusted.invalid/steal"], ["poll_url": "https://console.mistral.ai/outside-api"],
        ["poll_url": "https://user:password@console.mistral.ai/api/poll"],
        ["poll_url": "https://console.mistral.ai/api/%2e%2e/admin"],
        ["poll_url": "http://console.mistral.ai/api/poll"], ["sign_in_url": "https://untrusted.invalid/login"],
        ["sign_in_url": "https://console.mistral.ai.evil.example/x"], ["process_id": "../other-process"],
        ["process_id": ""], ["expires_at": "not-a-date"], ["expires_at": "2029-12-31T23:00:00Z"]
    ])
    func `bad process metadata is refused before the browser or any poll`(patch: [String: String]) async {
        let transport = SequencedTransport([.json(200, Self.begun(patch)), .json(200, Self.completed)])
        await #expect(throws: SignInError.self, "\(patch)") {
            _ = try await SignInRunner(clock: StepClock()).run(flow(transport)) { _ in Issue.record("link shown") }
        }
        #expect(transport.sent.count == 1)
    }

    @Test(arguments: ["denied", "expired", "error", "unknown"])
    func `a terminal state is never exchanged`(status: String) async {
        let transport = SequencedTransport([
            .json(200, Self.begun()), .json(200, #"{"status":"\#(status)","message":"server-text"}"#)
        ])
        await #expect(throws: SignInError.self) {
            _ = try await SignInRunner(clock: StepClock()).run(flow(transport)) { _ in }
        }
        #expect(transport.sent.count == 2)
    }

    @Test func `a denied sign-in and an expired one are told apart, and 410 is expiry`() async {
        for (reply, expected) in [
            (SequencedTransport.Reply.json(200, #"{"status":"denied"}"#), SignInError.denied),
            (.json(200, #"{"status":"expired"}"#), .expired), (.json(410, "gone"), .expired)
        ] {
            do {
                _ = try await run([.json(200, Self.begun()), reply])
                Issue.record("signed in")
            } catch let error as SignInError { #expect(error == expected) } catch { Issue.record("\(error)") }
        }
    }

    @Test func `completion without a usable exchange token is refused`() async {
        for body in [#"{"status":"completed"}"#, #"{"status":"completed","exchange_token":"a b"}"#] {
            await #expect(throws: SignInError.invalidResponse("exchange_token")) {
                _ = try await run([.json(200, Self.begun()), .json(200, body)])
            }
        }
    }

    @Test func `an exchange that returns no usable key stores nothing`() async {
        for body in [
            #"{}"#, #"{"api_key":""}"#, #"{"api_key":"a b"}"#, #"{"api_key":"a\nb"}"#,
            "{\"api_key\":\"\(String(repeating: "k", count: 20_000))\"}"
        ] {
            await #expect(throws: SignInError.invalidResponse("api_key")) {
                _ = try await run([.json(200, Self.begun()), .json(200, Self.completed), .json(200, body)])
            }
        }
    }

    @Test func `a failed exchange is reported without repeating the exchange token, and is not retried`() async {
        let transport = SequencedTransport([
            .json(200, Self.begun()), .json(200, Self.completed), .failure(HTTPTransportError.failed("reset"))
        ])
        do {
            _ = try await SignInRunner(clock: StepClock()).run(flow(transport)) { _ in }
            Issue.record("signed in")
        } catch { #expect(!"\(error)".contains("xchg-token")) }
        #expect(transport.sent.count == 3)
    }

    @Test(.timeLimit(.minutes(1)))
    func `the session's own expiry bounds the wait, here a minute`() async {
        let clock = StepClock()
        await #expect(throws: SignInError.timedOut) {
            _ = try await run([.json(200, Self.begun()), .json(200, Self.pending)], clock: clock)
        }
        #expect(clock.sleeps.reduce(.zero, +) == .seconds(60))
    }

    @Test func `cancelling when the link is shown sends no poll and no exchange`() async {
        let transport = SequencedTransport([
            .json(200, Self.begun()), .json(200, Self.completed), .json(200, Self.exchanged)
        ])
        let task = Task {
            try await SignInRunner(clock: StepClock())
                .run(flow(transport)) { _ in withUnsafeCurrentTask { $0?.cancel() } }
        }
        await #expect(throws: SignInError.cancelled) { _ = try await task.value }
        #expect(transport.sent.count == 1)
    }
}
