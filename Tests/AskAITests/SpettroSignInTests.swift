import Foundation
import Testing

@testable import AskAI

/// Spettro's device sign-in: a session id, a browser link, then polling for the device key (diary 18, from
/// pi-integrations' `spettro/provider.ts` and the cases its tests pin).
@Suite("Spettro's sign-in returns a device key, and trusts nothing the server says about where to go")
struct SpettroSignInTests {
    private static let browser = #"{"browser_url":"https://spettro.app/auth/cli?session=s"}"#
    private static let complete = #"{"status":"complete","api_key":"spk-device-key"}"#
    private static let pending = #"{"status":"pending"}"#

    private func run(
        _ replies: [SequencedTransport.Reply], base: String = "https://api.spettro.app", clock: StepClock = StepClock()
    ) async throws -> (key: StoredKey, transport: SequencedTransport, links: [URL], clock: StepClock) {
        let transport = SequencedTransport(replies)
        let flow = try SpettroSignIn(transport: transport, base: base, sessionID: "sess-1", now: { 42 })
        let links = LinkLog()
        let key = try await SignInRunner(clock: clock).run(flow) { links.add($0) }
        return (key, transport, links.all, clock)
    }

    @Test func `a full sign-in shows the link, waits before each poll, and returns the key`() async throws {
        let done = try await run([
            .json(200, Self.browser), .json(200, Self.pending), .json(200, Self.complete)
        ])
        #expect(done.key == StoredKey(key: "spk-device-key", obtainedAt: 42))
        #expect(done.links.map(\.absoluteString) == ["https://spettro.app/auth/cli?session=s"])
        #expect(done.transport.sent.map(\.method) == ["POST", "GET", "GET"])
        #expect(done.transport.sent[0].url.absoluteString == "https://api.spettro.app/auth/initiate")
        #expect(done.transport.sent[0].bodyText == #"{"session_id":"sess-1"}"#)
        #expect(done.transport.sent[1].url.absoluteString == "https://api.spettro.app/auth/poll/sess-1")
        #expect(done.clock.sleeps == [.seconds(2), .seconds(2)])
    }

    @Test func `the sign-in cannot be sent to another host through the environment`() {
        for base in [
            "http://api.spettro.example", "https://user:pw@api.spettro.app", "https://x.example/?a=b", "ftp://x"
        ] {
            #expect(throws: SignInError.self, "\(base)") {
                try SpettroSignIn(
                    transport: SequencedTransport([.json(200, "{}")]), base: base, sessionID: "s", now: { 0 })
            }
        }
        #expect(throws: Never.self) {
            try SpettroSignIn(
                transport: SequencedTransport([.json(200, "{}")]), base: "http://127.0.0.1:9000", sessionID: "s",
                now: { 0 })
        }
    }

    @Test(arguments: [
        #"{"browser_url":"http://spettro.app/login"}"#, #"{"browser_url":"https://u:p@spettro.app/"}"#,
        #"{"browser_url":"javascript:alert(1)"}"#, #"{"browser_url":7}"#, #"{}"#
    ])
    func `a browser link that is not plain https is refused before anything is polled`(body: String) async {
        let transport = SequencedTransport([.json(200, body), .json(200, Self.complete)])
        let flow = try! SpettroSignIn(transport: transport, base: "https://api.spettro.app", sessionID: "s", now: { 0 })
        await #expect(throws: SignInError.self) { _ = try await SignInRunner(clock: StepClock()).run(flow) { _ in } }
        #expect(transport.sent.count == 1)
    }

    @Test(arguments: [
        (200, #"{"status":"expired"}"#, SignInError.expired), (404, "gone", SignInError.expired),
        (200, #"{"status":"mystery"}"#, SignInError.invalidResponse("status")),
        (200, #"{"status":"complete"}"#, SignInError.invalidResponse("api_key")),
        (200, #"{"status":"complete","api_key":"has space"}"#, SignInError.invalidResponse("api_key")),
        (200, #"{"status":"complete","api_key":""}"#, SignInError.invalidResponse("api_key")),
        (500, "oops", SignInError.rejected(status: 500)), (200, "not json", SignInError.invalidResponse("body"))
    ])
    func `every answer that is not a key or still pending ends the sign-in`(
        status: Int, body: String, expected: SignInError
    ) async throws {
        do {
            _ = try await run([.json(200, Self.browser), .json(status, body)])
            Issue.record("signed in")
        } catch let error as SignInError { #expect(error == expected) }
    }

    @Test(.timeLimit(.minutes(1)))
    func `a session that never completes times out after ten minutes, not before`() async throws {
        let clock = StepClock()
        await #expect(throws: SignInError.timedOut) {
            _ = try await run([.json(200, Self.browser), .json(200, Self.pending)], clock: clock)
        }
        #expect(clock.sleeps.reduce(.zero, +) == .seconds(600))
    }

    @Test func `cancelling after the link is shown polls nothing`() async throws {
        let transport = SequencedTransport([.json(200, Self.browser), .json(200, Self.complete)])
        let flow = try SpettroSignIn(transport: transport, base: "https://api.spettro.app", sessionID: "s", now: { 0 })
        let task = Task {
            try await SignInRunner(clock: StepClock()).run(flow) { _ in withUnsafeCurrentTask { $0?.cancel() } }
        }
        await #expect(throws: SignInError.cancelled) { _ = try await task.value }
        #expect(transport.sent.count == 1)
    }

    @Test func `a transport failure never repeats the key`() async {
        let transport = SequencedTransport([.json(200, Self.browser), .failure(HTTPTransportError.failed("offline"))])
        let flow = try! SpettroSignIn(transport: transport, base: "https://api.spettro.app", sessionID: "s", now: { 0 })
        do { _ = try await SignInRunner(clock: StepClock()).run(flow) { _ in } } catch {
            #expect(!"\(error)".contains("spk-"))
            #expect("\(error)".contains("offline"))
        }
    }
}
