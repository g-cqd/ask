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
        var nextID = 1
    }

    private let state = Mutex(State())
    private let feed: AsyncThrowingStream<[UInt8], any Error>.Continuation
    private let serving: Task<Void, Never>
    private let output = Output()

    init(agent: ACPImplementation = ACPImplementation(name: "ask", version: "0")) {
        let (stream, feed) = AsyncThrowingStream<[UInt8], any Error>.makeStream()
        self.feed = feed
        let server = ACPServer(output: output, agent: agent)
        serving = Task { await server.run(reading: stream) }
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
                guard !message["method"].exists, let id = message["id"].int else {
                    state.others.append(message)
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

    /// The answer to request `id`, awaited.
    func answer(to id: Int) async -> JSON {
        await withCheckedContinuation { continuation in
            let ready = state.withLock { state -> JSON? in
                if let answer = state.answers.removeValue(forKey: id) { return answer }
                state.waiters[id] = continuation
                return nil
            }
            if let ready { continuation.resume(returning: ready) }
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
        await serving.value
        output.exchange.withLock { $0 = nil }
        return state.withLock { $0.others + $0.answers.sorted { $0.key < $1.key }.map(\.value) }
    }
}
