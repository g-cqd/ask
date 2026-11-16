internal import AskAI
internal import Foundation
internal import Synchronization
internal import Testing

@testable import AskMCP

/// A conversation that has ended its session sends nothing more on it. A message is sent by a task of its own, which may not have
/// reached the wire when the conversation closes: on a loaded machine the session's `DELETE` was then followed by that message's
/// `POST` (CI's debug tests, 2026-11-15).
@Suite("An HTTP transport that closed sends nothing after ending its session", .timeLimit(.minutes(1)))
struct HTTPMCPCloseOrderTests {
    /// A sign-in that keeps one caller waiting for its header until the test lets it go, and says when that caller is waiting.
    final class Gate: MCPAuthorization {
        private let state = Mutex<
            (holds: Bool, held: CheckedContinuation<Void, Never>?, watcher: CheckedContinuation<Void, Never>?)
        >(
            (false, nil, nil)
        )

        /// The next caller waits.
        func holdNext() { state.withLock { $0.holds = true } }

        /// Returns once a caller is waiting.
        func waiting() async {
            await withCheckedContinuation { continuation in
                let already = state.withLock { state -> Bool in
                    if state.held != nil { return true }
                    state.watcher = continuation
                    return false
                }
                if already { continuation.resume() }
            }
        }

        /// Lets the waiting caller go.
        func release() {
            let held = state.withLock { state in
                defer { state.held = nil }
                return state.held
            }
            held?.resume()
        }

        func header() async -> String? {
            guard state.withLock({ $0.holds }) else { return "Bearer t" }
            await withCheckedContinuation { continuation in
                let watcher = state.withLock { state in
                    state.holds = false
                    state.held = continuation
                    defer { state.watcher = nil }
                    return state.watcher
                }
                watcher?.resume()
            }
            return "Bearer t"
        }

        func refused(_ challenge: MCPAuthChallenge?) async -> Bool { false }
    }

    @Test func `a message still on its way when the conversation closed is not sent after the session ended`()
        async throws
    {
        let http = ScriptedHTTP { seen in
            seen.rpcMethod == "initialize"
                ? ScriptedHTTP.json(#"{"jsonrpc":"2.0","id":1,"result":{}}"#, headers: ["mcp-session-id": "s"])
                : ScriptedHTTP.status(202)
        }
        let gate = Gate()
        let transport = try HTTPMCPTransport(url: HTTPMCP.url, userAgent: "ask-test/1", http: http, authorization: gate)
        var incoming = transport.incoming.makeAsyncIterator()
        try await HTTPMCP.send(#"{"jsonrpc":"2.0","id":1,"method":"initialize"}"#, on: transport)
        _ = await HTTPMCP.next(&incoming)
        gate.holdNext()
        let note = Array(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#.utf8)
        let onItsWay = Task { await transport.exchange(note, requestID: nil) }
        await gate.waiting()
        await transport.close()
        gate.release()
        await onItsWay.value
        let sent: [String] = http.requests.map(\.method)
        #expect(sent == ["POST", "DELETE"], "the session was ended, then spoken on: \(sent)")
    }
}
