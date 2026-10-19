internal import CryptoKit
internal import Foundation
internal import Testing

@testable import AskAI

/// Codex's browser sign-in end to end, with the real callback listener and a scripted token endpoint. The test plays
/// the browser: it reads the state out of the address ask shows and calls back with it, as the provider's redirect does.
@Suite(
    "Codex's browser sign-in waits for the redirect, or a pasted address, and exchanges the code it gets",
    .timeLimit(.minutes(1)))
struct CodexBrowserSignInTests {
    private static let access: String = {
        let claims = #"{"https://api.openai.com/auth":{"chatgpt_account_id":"acct_5"}}"#
        return [Base64URL.encode(Array(#"{"alg":"none"}"#.utf8)), Base64URL.encode(Array(claims.utf8)), "sig"]
            .joined(separator: ".")
    }()
    private static var tokens: String { #"{"access_token":"\#(access)","refresh_token":"rt-b","expires_in":3600}"# }

    private func query(_ prompt: SignInPrompt, _ name: String) -> String {
        URLComponents(url: prompt.url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == name }?.value
            ?? ""
    }

    private func flow(_ transport: SequencedTransport, listener: LoopbackListener?) -> CodexBrowserSignIn {
        CodexBrowserSignIn(
            transport: transport, now: { 50 },
            bind: { _ throws(LoopbackError) in
                guard let listener else { throw .bindFailed(errno: 48) }
                return listener
            })
    }

    private func verifier(_ body: String) -> String {
        body.split(separator: "&").first { $0.hasPrefix("code_verifier=") }.map { String($0.dropFirst(14)) } ?? ""
    }

    @Test func `the redirect's code is exchanged with the verifier whose challenge started it`() async throws {
        let listener = try LoopbackListener.bind(port: 0)
        let transport = SequencedTransport([.json(200, Self.tokens)])
        let prompts = PromptLog()
        let credentials = try await flow(transport, listener: listener)
            .run(
                show: { prompt in
                    prompts.add(prompt)
                    let (state, port) = (self.query(prompt, "state"), listener.port)
                    Task { _ = await RawClient.get("/auth/callback?code=thecode12345&state=\(state)", port: port) }
                }, paste: { nil })
        #expect(credentials.accountID == "acct_5")
        #expect(credentials.refreshToken == "rt-b")
        let prompt = try #require(prompts.all.first)
        #expect(prompt.instructions?.contains("browser") == true)
        let body = try #require(transport.sent.first?.bodyText)
        #expect(body.contains("code=thecode12345"))
        #expect(body.contains("redirect_uri=http%3A%2F%2Flocalhost%3A1455%2Fauth%2Fcallback"))
        let challenge = Base64URL.encode(Array(SHA256.hash(data: Array(verifier(body).utf8))))
        #expect(self.query(prompt, "code_challenge") == challenge, "the exchange must prove the sign-in it belongs to")
        #expect(RawClient.refused(port: listener.port), "the port is free once the redirect is in")
    }

    @Test func `every sign-in has its own state, with room for entropy`() async throws {
        let prompts = PromptLog()
        for _ in 0 ..< 3 {
            let listener = try LoopbackListener.bind(port: 0)
            let transport = SequencedTransport([.json(200, Self.tokens)])
            _ = try await flow(transport, listener: listener)
                .run(
                    show: { prompt in
                        prompts.add(prompt)
                        let (state, port) = (self.query(prompt, "state"), listener.port)
                        Task { _ = await RawClient.get("/auth/callback?code=thecode12345&state=\(state)", port: port) }
                    }, paste: { nil })
        }
        let states = Set(prompts.all.map { query($0, "state") })
        #expect(states.count == 3)
        #expect(states.allSatisfy { $0.count >= 22 })
    }

    @Test func `with the port taken the user is asked to paste the redirect address, and it is used`() async throws {
        let transport = SequencedTransport([.json(200, Self.tokens)])
        let prompts = PromptLog()
        let credentials = try await flow(transport, listener: nil)
            .run(
                show: { prompts.add($0) },
                paste: { [prompts] in
                    let state = prompts.all.first.map { self.query($0, "state") } ?? ""
                    return "http://localhost:1455/auth/callback?code=pastedcode123&state=\(state)"
                })
        #expect(credentials.accountID == "acct_5")
        #expect(prompts.all.first?.instructions?.contains("paste") == true)
        #expect(transport.sent.first?.bodyText.contains("code=pastedcode123") == true)
    }

    @Test func `a pasted address for another sign-in is refused before any request`() async {
        let transport = SequencedTransport([.json(200, Self.tokens)])
        await #expect(throws: SignInError.invalidResponse("pasted address")) {
            _ = try await flow(transport, listener: nil)
                .run(
                    show: { _ in }, paste: { "http://localhost:1455/auth/callback?code=pastedcode123&state=not-mine" })
        }
        #expect(transport.sent.isEmpty)
    }

    @Test func `no pasted input at all is a cancelled sign-in`() async {
        await #expect(throws: SignInError.cancelled) {
            _ = try await flow(SequencedTransport([.json(200, Self.tokens)]), listener: nil)
                .run(show: { _ in }, paste: { nil })
        }
    }

    @Test func `the provider's error ends the sign-in without an exchange`() async throws {
        let listener = try LoopbackListener.bind(port: 0)
        let transport = SequencedTransport([.json(200, Self.tokens)])
        await #expect(throws: SignInError.authorizationFailed("access_denied")) {
            _ = try await flow(transport, listener: listener)
                .run(
                    show: { prompt in
                        let (state, port) = (self.query(prompt, "state"), listener.port)
                        Task {
                            _ = await RawClient.get("/auth/callback?error=access_denied&state=\(state)", port: port)
                        }
                    }, paste: { nil })
        }
        #expect(transport.sent.isEmpty)
    }

    @Test func `a refused exchange is reported`() async throws {
        let listener = try LoopbackListener.bind(port: 0)
        let transport = SequencedTransport([.json(400, #"{"error":"invalid_grant"}"#)])
        await #expect(throws: SignInError.rejected(status: 400)) {
            _ = try await flow(transport, listener: listener)
                .run(
                    show: { prompt in
                        let (state, port) = (self.query(prompt, "state"), listener.port)
                        Task { _ = await RawClient.get("/auth/callback?code=thecode12345&state=\(state)", port: port) }
                    }, paste: { nil })
        }
    }

    @Test func `cancelling the sign-in frees the port`() async throws {
        let listener = try LoopbackListener.bind(port: 0)
        let port = listener.port
        let transport = SequencedTransport([.json(200, Self.tokens)])
        let task = Task { try await flow(transport, listener: listener).run(show: { _ in }, paste: { nil }) }
        // A reply to a stray request proves the sign-in is waiting on the listener, so the cancel lands on it.
        _ = await RawClient.get("/ping", port: port)
        task.cancel()
        _ = await task.result
        #expect(RawClient.refused(port: port))
    }
}
