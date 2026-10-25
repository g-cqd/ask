public import AskAI
internal import Foundation
internal import Synchronization

/// A web server played by the test: it records every request and answers with what the test's handler returns, so the HTTP transport is
/// tested without a network (ADR-0096). Nothing sleeps: a test waits for a request to arrive, not for time to pass.
final class ScriptedHTTP: HTTPTransport {
    /// What a request looked like to the server.
    struct Seen: Sendable {
        let method: String
        let headers: [String: String]
        let body: String

        /// The JSON-RPC method in the body, if it is a message.
        var rpcMethod: String? {
            guard let range = body.range(of: #""method":""#) else { return nil }
            return String(body[range.upperBound...].prefix { $0 != "\"" })
        }
    }

    private let state = Mutex<(seen: [Seen], waiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)])>(
        ([], []))
    private let handler: Mutex<@Sendable (Seen) async throws -> HTTPStreamingResponse>

    init(
        _ handler: @escaping @Sendable (Seen) async throws -> HTTPStreamingResponse = { _ in ScriptedHTTP.status(202) }
    ) {
        self.handler = Mutex(handler)
    }

    /// Replaces what the server answers.
    func answer(_ handler: @escaping @Sendable (Seen) async throws -> HTTPStreamingResponse) {
        self.handler.withLock { $0 = handler }
    }

    /// Every request, in the order they arrived.
    var requests: [Seen] { state.withLock { $0.seen } }

    /// Returns once `count` requests have arrived.
    func waitForRequests(_ count: Int) async {
        await withCheckedContinuation { continuation in
            let ready = state.withLock { state -> Bool in
                if state.seen.count >= count { return true }
                state.waiters.append((count, continuation))
                return false
            }
            if ready { continuation.resume() }
        }
    }

    func send(_ request: HTTPRequest) async throws -> HTTPStreamingResponse {
        var headers: [String: String] = [:]
        for (name, value) in request.headers { headers[name.lowercased()] = value }
        let seen = Seen(method: request.method, headers: headers, body: String(decoding: request.body, as: UTF8.self))
        let ready = state.withLock { state -> [CheckedContinuation<Void, Never>] in
            state.seen.append(seen)
            var ready: [CheckedContinuation<Void, Never>] = []
            state.waiters.removeAll { waiter in
                guard state.seen.count >= waiter.count else { return false }
                ready.append(waiter.continuation)
                return true
            }
            return ready
        }
        for continuation in ready { continuation.resume() }
        return try await handler.withLock { $0 }(seen)
    }

    /// A reply with no body, such as `202`.
    static func status(_ code: Int, headers: [String: String] = [:]) -> HTTPStreamingResponse {
        chunks(code, [], headers: headers)
    }

    /// A JSON reply.
    static func json(_ body: String, headers: [String: String] = [:]) -> HTTPStreamingResponse {
        chunks(200, [body], headers: headers.merging(["content-type": "application/json"]) { $1 })
    }

    /// A server-sent-events reply, delivered in these pieces.
    static func events(_ pieces: [String], headers: [String: String] = [:]) -> HTTPStreamingResponse {
        chunks(200, pieces, headers: headers.merging(["content-type": "text/event-stream"]) { $1 })
    }

    /// A reply with this status, headers and body pieces.
    static func chunks(_ code: Int, _ pieces: [String], headers: [String: String] = [:]) -> HTTPStreamingResponse {
        let (body, continuation) = AsyncThrowingStream<[UInt8], any Error>.makeStream()
        for piece in pieces { continuation.yield(Array(piece.utf8)) }
        continuation.finish()
        return HTTPStreamingResponse(status: code, headers: headers, body: body)
    }
}
