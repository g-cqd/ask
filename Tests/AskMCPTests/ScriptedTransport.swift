internal import AemiJSON
internal import Foundation
internal import Synchronization

@testable import AskMCP

/// A server played by the test: it records every message the client sends and answers by method, so the client's protocol behaviour is
/// tested without a process (ADR-0096). Nothing here sleeps; a reply is made when its request arrives, or when the test pushes it.
final class ScriptedTransport: MCPTransport {
    /// One message the client sent.
    struct Sent: Sendable {
        let line: String
        let method: String?
        /// The request's id as written (`7`, or `"x"`), nil for a notification or a response.
        let id: String?
        let params: String?

        /// A reply to this request: a result, written as JSON.
        func result(_ json: String) -> String { #"{"jsonrpc":"2.0","id":\#(id ?? "null"),"result":\#(json)}"# }

        /// A JSON-RPC error reply to this request.
        func failure(_ code: Int, _ message: String) -> String {
            #"{"jsonrpc":"2.0","id":\#(id ?? "null"),"error":{"code":\#(code),"message":"\#(message)"}}"#
        }
    }

    let incoming: AsyncStream<[UInt8]>
    private let continuation: AsyncStream<[UInt8]>.Continuation
    private let state = Mutex<
        (
            sent: [Sent], handlers: [String: @Sendable (Sent) -> [String]], closed: Bool,
            waiters: [(method: String?, count: Int, continuation: CheckedContinuation<Void, Never>)]
        )
    >(([], [:], false, []))

    init() { (incoming, continuation) = AsyncStream.makeStream(of: [UInt8].self) }

    /// Answers requests for `method` with the lines `reply` returns, in order.
    func on(_ method: String, _ reply: @escaping @Sendable (Sent) -> [String]) {
        state.withLock { $0.handlers[method] = reply }
    }

    /// Everything the client sent, in order.
    var sent: [Sent] { state.withLock { $0.sent } }

    /// What the client sent for `method`.
    func sent(_ method: String) -> [Sent] { sent.filter { $0.method == method } }

    /// Whether the client closed the transport.
    var isClosed: Bool { state.withLock { $0.closed } }

    /// Returns once the client has sent `count` messages for `method`: an event, not a wait for time to pass.
    func waitUntilSent(_ method: String, count: Int = 1) async {
        await withCheckedContinuation { continuation in
            let ready = state.withLock { state -> Bool in
                if state.sent.filter({ $0.method == method }).count >= count { return true }
                state.waiters.append((method, count, continuation))
                return false
            }
            if ready { continuation.resume() }
        }
    }

    /// Returns once the client has written a message that is a reply (it has an id and no method).
    func waitUntilSentReply() async {
        await withCheckedContinuation { continuation in
            let ready = state.withLock { state -> Bool in
                if state.sent.contains(where: { $0.method == nil && $0.id != nil }) { return true }
                state.waiters.append((nil, 1, continuation))
                return false
            }
            if ready { continuation.resume() }
        }
    }

    /// A message from the server that nothing asked for, or a reply the test chose to hold back.
    func push(_ line: String) { continuation.yield(Array(line.utf8)) }

    /// The server goes away.
    func end() { continuation.finish() }

    func send(_ message: [UInt8]) async throws {
        let sent = Self.parse(message)
        let (replies, ready) = state.withLock { state -> ([String], [CheckedContinuation<Void, Never>]) in
            state.sent.append(sent)
            var ready: [CheckedContinuation<Void, Never>] = []
            state.waiters.removeAll { waiter in
                let matching =
                    waiter.method == nil
                    ? state.sent.filter { $0.method == nil && $0.id != nil }.count
                    : state.sent.filter { $0.method == waiter.method }.count
                guard matching >= waiter.count else { return false }
                ready.append(waiter.continuation)
                return true
            }
            guard let method = sent.method, sent.id != nil else { return ([], ready) }
            return (state.handlers[method]?(sent) ?? [sent.failure(-32601, "Method not found")], ready)
        }
        for reply in replies { push(reply) }
        for continuation in ready { continuation.resume() }
    }

    func close() async {
        state.withLock { $0.closed = true }
        continuation.finish()
    }

    private static func parse(_ message: [UInt8]) -> Sent {
        let line = String(decoding: message, as: UTF8.self)
        guard let document = try? AemiJSON.parse(message, options: JSONParseOptions(recordsContainerSpans: true)) else {
            return Sent(line: line, method: nil, id: nil, params: nil)
        }
        let root = document.root
        let id = root["id"].withRawJSONBytes { String(decoding: $0, as: UTF8.self) }
        let params = root["params"].withRawJSONBytes { String(decoding: $0, as: UTF8.self) }
        return Sent(line: line, method: root["method"].string, id: id, params: params)
    }
}
