import AemiJSON
import AemiJSONRPC
import Synchronization

@testable import AskACP

/// A client of a server, in memory: it sends a line, and waits for the answer to that request, with no clock. What the server
/// writes besides answers (notifications, its own requests) is kept in order.
final class ACPExchange: JSONRPCSink, Sendable {
    private struct State {
        var pending: [UInt8] = []
        var answers: [Int: JSON] = [:]
        var waiters: [Int: CheckedContinuation<JSON, Never>] = [:]
        var others: [JSON] = []
        var log: [JSON] = []
        var nextID = 1
    }

    private let state = Mutex(State())
    private let feed: AsyncThrowingStream<[UInt8], any Error>.Continuation
    private let served = Mailbox<Bool>()
    private let asked = Mailbox<JSON>()
    private let output = Output()

    init(agent: ACPImplementation = ACPImplementation(name: "ask", version: "0"), sessions: ACPSession.Source? = nil) {
        let (stream, feed) = AsyncThrowingStream<[UInt8], any Error>.makeStream()
        self.feed = feed
        let server = ACPServer(output: output, agent: agent, sessions: sessions)
        Task { [served] in
            await server.run(reading: stream)
            served.post(true)
        }
        output.exchange.withLock { $0 = self }
    }

    /// The server's output, which reaches the exchange once it exists: the server is made before `self` is whole.
    private final class Output: JSONRPCSink {
        let exchange = Mutex<ACPExchange?>(nil)
        func write(_ bytes: [UInt8]) async throws { try await exchange.withLock { $0 }?.write(bytes) }
    }

    func write(_ bytes: [UInt8]) async throws {
        let resumed = state.withLock { state -> [(CheckedContinuation<JSON, Never>, JSON)] in
            state.pending += bytes
            var resumed: [(CheckedContinuation<JSON, Never>, JSON)] = []
            while let newline = state.pending.firstIndex(of: 0x0A) {
                let line = Array(state.pending[..<newline])
                state.pending.removeSubrange(...newline)
                guard let message = try? AemiJSON.parse(line).root else { continue }
                state.log.append(message)
                guard !message["method"].exists, let id = message["id"].int else {
                    state.others.append(message)
                    // A request of the server's own, which the test answers as the client's person would.
                    if message["method"].exists, message["id"].exists { asked.post(message) }
                    continue
                }
                if let waiter = state.waiters.removeValue(forKey: id) {
                    resumed.append((waiter, message))
                } else {
                    state.answers[id] = message
                }
            }
            return resumed
        }
        for (waiter, message) in resumed { waiter.resume(returning: message) }
    }

    /// Everything the server has written so far, in the order it wrote it.
    var log: [JSON] { state.withLock { $0.log } }

    /// The `session/update` notifications written so far, each as its `params`.
    var updates: [JSONValue] {
        log.filter { $0["method"].string == "session/update" }.map { JSONValue($0["params"]) }
    }

    /// The next request the server makes of the client, awaited; nil when the test is cancelled first.
    func nextRequest() async -> JSON? { await asked.next() }

    /// Answers the server's request `request` with `result` (JSON text), or with an error when `result` is nil.
    func respond(to request: JSON?, _ result: String?) {
        let id = request?["id"].int ?? -1
        let body = result.map { #""result":\#($0)"# } ?? #""error":{"code":-32603,"message":"the client failed"}"#
        send(raw: [#"{"jsonrpc":"2.0","id":\#(id),\#(body)}"# + "\n"])
    }

    /// Sends `text` as it is, in the pieces given: what a client that is not well behaved writes.
    func send(raw pieces: [String]) { for piece in pieces { feed.yield(Array(piece.utf8)) } }

    /// Sends a request for `method` with `params` (JSON text) and returns the whole answer, once the server has written it.
    func request(_ method: String, _ params: String? = nil) async -> JSON {
        let id = state.withLock { state -> Int in
            defer { state.nextID += 1 }
            return state.nextID
        }
        let tail = params.map { #","params":\#($0)"# } ?? ""
        send(raw: [#"{"jsonrpc":"2.0","id":\#(id),"method":"\#(method)"\#(tail)}"# + "\n"])
        return await answer(to: id)
    }

    /// What a wait for an answer returns when the test is cancelled (its time limit) before the server answered: a broken server
    /// then fails the test instead of holding it for ever.
    static let unanswered = #"{"error":{"code":0,"message":"the test ended before the server answered"}}"#

    /// The answer to request `id`, awaited.
    func answer(to id: Int) async -> JSON {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let ready = state.withLock { state -> JSON? in
                    if let answer = state.answers.removeValue(forKey: id) { return answer }
                    if Task.isCancelled { return try? AemiJSON.parse(Array(Self.unanswered.utf8)).root }
                    state.waiters[id] = continuation
                    return nil
                }
                if let ready { continuation.resume(returning: ready) }
            }
        } onCancel: {
            let waiter = state.withLock { $0.waiters.removeValue(forKey: id) }
            if let waiter, let none = try? AemiJSON.parse(Array(Self.unanswered.utf8)).root {
                waiter.resume(returning: none)
            }
        }
    }

    /// `initialize`, as a client opens: the answer.
    func initialize(version: Int = 1) async -> JSON {
        await request(
            "initialize",
            #"{"protocolVersion":\#(version),"clientCapabilities":{},"clientInfo":{"name":"probe","version":"1"}}"#
        )
    }

    /// Ends the client's side and waits for the server to finish; returns what it wrote that answered no request of `request`.
    func end() async -> [JSON] {
        feed.finish()
        // Not the task's value, which a cancelled test would wait on for ever when the server never answers a request.
        _ = await served.next()
        output.exchange.withLock { $0 = nil }
        return state.withLock { $0.others + $0.answers.sorted { $0.key < $1.key }.map(\.value) }
    }
}
