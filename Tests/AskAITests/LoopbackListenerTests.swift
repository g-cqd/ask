internal import Foundation
internal import Testing

@testable import AskAI

/// The callback listener on a real socket, driven by a raw client so it can be sent what no browser would send. Each
/// rule is one pi-integrations' loopback tests pin for the same reason: this server is reachable by any page the user
/// has open while they sign in.
@Suite(
    "The callback listener returns the code from the first valid callback, and ignores everything else",
    .timeLimit(.minutes(1)))
struct LoopbackListenerTests {
    private static let path = "/auth/callback"

    private func listener() throws -> LoopbackListener { try LoopbackListener.bind(port: 0) }

    /// The wait for a callback, running while the test plays the browser.
    private func waiting(_ listener: LoopbackListener, state: String) -> Task<String, any Error> {
        Task { try await listener.authorization(path: Self.path, state: state) }
    }

    @Test func `a valid callback gives its code, a static success page, and frees the port`() async throws {
        let listener = try listener()
        let port = listener.port
        let code = waiting(listener, state: "s1")
        let reply = await RawClient.get("\(Self.path)?code=abc123&state=s1", port: port)
        #expect(try await code.value == "abc123")
        #expect(reply?.hasPrefix("HTTP/1.1 200") == true)
        #expect(reply?.contains("Cache-Control: no-store") == true)
        #expect(reply?.contains("Referrer-Policy: no-referrer") == true)
        #expect(reply?.contains("abc123") == false, "a page must never reflect the query")
        #expect(RawClient.refused(port: port), "the first valid callback ends the listening")
    }

    @Test func `a wrong or missing state is refused and does not end the sign-in`() async throws {
        let listener = try listener()
        let code = waiting(listener, state: "right")
        for target in ["code=x&state=wrong", "code=x", "state=right", "code=&state=right"] {
            let reply = await RawClient.get("\(Self.path)?\(target)", port: listener.port)
            #expect(reply?.hasPrefix("HTTP/1.1 400") == true, "\(target)")
        }
        _ = await RawClient.get("\(Self.path)?code=real&state=right", port: listener.port)
        #expect(try await code.value == "real")
    }

    @Test func `a provider error with the right state ends the sign-in with its allowlisted code`() async throws {
        let listener = try listener()
        let code = waiting(listener, state: "s")
        _ = await RawClient.get("\(Self.path)?error=access_denied&state=s", port: listener.port)
        await #expect(throws: SignInError.authorizationFailed("access_denied")) { _ = try await code.value }
    }

    @Test func `an error with the wrong state, or an unsafe code, cannot end it or be echoed`() async throws {
        let listener = try listener()
        let code = waiting(listener, state: "s")
        _ = await RawClient.get("\(Self.path)?error=access_denied&state=other", port: listener.port)
        _ = await RawClient.get("\(Self.path)?error=%3Cscript%3E&state=s", port: listener.port)
        await #expect(throws: SignInError.authorizationFailed("error")) { _ = try await code.value }
    }

    @Test func `only a GET on the exact path is served`() async throws {
        let listener = try listener()
        let code = waiting(listener, state: "s")
        let wrongPath = await RawClient.get("/other?code=x&state=s", port: listener.port)
        let post = await RawClient.send(
            "POST \(Self.path)?code=x&state=s HTTP/1.1\r\nHost: 127.0.0.1:\(listener.port)\r\nContent-Length: 0\r\n\r\n",
            to: listener.port)
        #expect(wrongPath?.hasPrefix("HTTP/1.1 404") == true)
        #expect(post?.hasPrefix("HTTP/1.1 404") == true)
        _ = await RawClient.get("\(Self.path)?code=ok&state=s", port: listener.port)
        #expect(try await code.value == "ok")
    }

    @Test func `a host that is not this machine is refused, which blocks DNS rebinding`() async throws {
        let listener = try listener()
        let code = waiting(listener, state: "s")
        for host in ["evil.example", "evil.example:\(listener.port)", "localhost.evil.example:\(listener.port)"] {
            let reply = await RawClient.get("\(Self.path)?code=x&state=s", port: listener.port, host: host)
            #expect(reply?.hasPrefix("HTTP/1.1 404") == true, "\(host)")
        }
        let none = await RawClient.send("GET \(Self.path)?code=x&state=s HTTP/1.0\r\n\r\n", to: listener.port)
        #expect(none?.hasPrefix("HTTP/1.1 404") == true)
        _ = await RawClient.get("\(Self.path)?code=ok&state=s", port: listener.port, host: "localhost:\(listener.port)")
        #expect(try await code.value == "ok")
    }

    @Test func `garbage and oversized requests are refused without ending the sign-in`() async throws {
        let listener = try listener()
        let code = waiting(listener, state: "s")
        let junk = await RawClient.send(String(repeating: "A", count: 20_000) + "\r\n\r\n", to: listener.port)
        #expect(junk?.hasPrefix("HTTP/1.1 400") == true)
        let binary = await RawClient.send("\u{1}\u{2}\u{3}\r\n\r\n", to: listener.port)
        #expect(binary?.hasPrefix("HTTP/1.1 400") == true)
        _ = await RawClient.get("\(Self.path)?code=ok&state=s", port: listener.port)
        #expect(try await code.value == "ok")
    }

    @Test(.timeLimit(.minutes(1)))
    func `a connection that says nothing does not hold the sign-in hostage`() async throws {
        let listener = try listener()
        let code = waiting(listener, state: "s")
        let stalled = Task { await RawClient.stall(port: listener.port, seconds: 4) }
        try await Task.sleep(for: .milliseconds(150))
        let started = ContinuousClock.now
        _ = await RawClient.get("\(Self.path)?code=ok&state=s", port: listener.port)
        #expect(try await code.value == "ok")
        #expect(
            ContinuousClock.now - started < .seconds(3), "a stalled tab may delay the callback by its timeout, not more"
        )
        await stalled.value
    }

    /// How a wait ended, or nil if it had not within `limit`. A wait that will not end is closed, so a broken
    /// cancel path fails this test in seconds instead of hanging the suite.
    private func settled(
        _ wait: Task<String, any Error>, on listener: LoopbackListener, within limit: Duration = .seconds(5)
    )
        async -> Result<String, any Error>?
    {
        await withTaskGroup(of: Result<String, any Error>?.self) { group in
            group.addTask { await wait.result }
            group.addTask {
                try? await Task.sleep(for: limit)
                return nil
            }
            let first = await group.next() ?? nil
            if first == nil { listener.close() }
            group.cancelAll()
            return first
        }
    }

    @Test func `cancelling stops the wait and frees the port`() async throws {
        let listener = try listener()
        let port = listener.port
        let wait = waiting(listener, state: "s")
        try await Task.sleep(for: .milliseconds(150))
        wait.cancel()
        guard case .failure(let error)? = await settled(wait, on: listener) else {
            Issue.record("cancelling did not end the wait")
            return
        }
        #expect(error as? SignInError == .cancelled)
        #expect(RawClient.refused(port: port))
    }

    @Test func `a port already listened on cannot be bound, so the caller can ask for a pasted address`() throws {
        let first = try listener()
        defer { first.close() }
        #expect(throws: LoopbackError.self) { try LoopbackListener.bind(port: first.port) }
    }

    @Test func `closing a listener that never waited frees its port`() throws {
        let listener = try listener()
        let port = listener.port
        listener.close()
        #expect(RawClient.refused(port: port))
    }
}
