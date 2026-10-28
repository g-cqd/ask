import AemiRegex
import AskMCP
import Foundation
import Synchronization

/// A server played by the test, speaking JSON-RPC in memory: it answers `initialize`, `tools/list` and `tools/call`, can be made to
/// fail, to change its tools, or to go away. Nothing sleeps.
final class FakeMCPServer: MCPTransport {
    let incoming: AsyncStream<[UInt8]>
    private let continuation: AsyncStream<[UInt8]>.Continuation
    private struct State {
        var tools: [String]
        var refusesInitialize = false
        var holdsInitialize = false
        var diagnosis: String?
        var closed = false
        var calls: [(name: String, arguments: String)] = []
        var callReply: @Sendable (String, String) -> String = { name, _ in
            #"{"content":[{"type":"text","text":"ran \#(name)"}]}"#
        }
        var listings = 0
        var initializeWaiters: [CheckedContinuation<Void, Never>] = []
        var initializes = 0
    }
    private let state: Mutex<State>

    private let destructive: Set<String>

    /// A server with tools of these names, marking `destructive` as the server would (ADR-0111).
    init(tools: [String] = [], destructive: [String] = []) {
        self.destructive = Set(destructive)
        (incoming, continuation) = AsyncStream.makeStream(of: [UInt8].self)
        state = Mutex(State(tools: tools))
    }

    var calls: [(name: String, arguments: String)] { state.withLock { $0.calls } }
    var isClosed: Bool { state.withLock { $0.closed } }
    var listings: Int { state.withLock { $0.listings } }

    func setTools(_ names: [String]) { state.withLock { $0.tools = names } }
    /// The server never answers `initialize`: it is still starting.
    func holdInitialize() { state.withLock { $0.holdsInitialize = true } }
    /// What the transport says about why it failed, as a real one does.
    func diagnose(_ text: String) { state.withLock { $0.diagnosis = text } }
    var diagnostic: String? { state.withLock { $0.diagnosis } }
    func refuseInitialize() { state.withLock { $0.refusesInitialize = true } }
    func reply(to call: @escaping @Sendable (String, String) -> String) { state.withLock { $0.callReply = call } }

    /// Returns once the client has sent `initialize`.
    func waitForInitialize() async {
        await withCheckedContinuation { continuation in
            let ready = state.withLock { state -> Bool in
                if state.initializes > 0 { return true }
                state.initializeWaiters.append(continuation)
                return false
            }
            if ready { continuation.resume() }
        }
    }

    /// The server tells the client its tools changed.
    func announceChange() { push(#"{"jsonrpc":"2.0","method":"notifications/tools/list_changed"}"#) }

    /// The server goes away.
    func end() { continuation.finish() }

    private func push(_ line: String) { continuation.yield(Array(line.utf8)) }

    func send(_ message: [UInt8]) async throws {
        let text = String(decoding: message, as: UTF8.self)
        guard let id = capture(#""id":(\d+)"#, in: text),
            let method = capture(#""method":"([^"]+)""#, in: text)
        else { return }
        switch method {
            case "initialize":
                let waiting = state.withLock { state -> [CheckedContinuation<Void, Never>] in
                    state.initializes += 1
                    defer { state.initializeWaiters = [] }
                    return state.initializeWaiters
                }
                for waiter in waiting { waiter.resume() }
                if state.withLock({ $0.holdsInitialize }) { return }
                if state.withLock({ $0.refusesInitialize }) {
                    push(#"{"jsonrpc":"2.0","id":\#(id),"error":{"code":-32000,"message":"no thanks"}}"#)
                } else {
                    push(
                        #"{"jsonrpc":"2.0","id":\#(id),"result":{"protocolVersion":"2025-06-18","capabilities":{"tools":{"listChanged":true}},"serverInfo":{"name":"fake","version":"1"}}}"#
                    )
                }
            case "tools/list":
                let names = state.withLock { state -> [String] in
                    state.listings += 1
                    return state.tools
                }
                let tools = names.map { name -> String in
                    let marked = destructive.contains(name) ? #","annotations":{"destructiveHint":true}"# : ""
                    return
                        #"{"name":"\#(name)","description":"does \#(name)","inputSchema":{"type":"object","properties":{"q":{"type":"string"}}}\#(marked)}"#
                }
                push(#"{"jsonrpc":"2.0","id":\#(id),"result":{"tools":[\#(tools.joined(separator: ","))]}}"#)
            case "tools/call":
                let name = capture(#""name":"([^"]+)""#, in: text) ?? ""
                let arguments = capture(#""arguments":(\{[^}]*\})"#, in: text) ?? "{}"
                let reply = state.withLock { state -> String in
                    state.calls.append((name, arguments))
                    return state.callReply(name, arguments)
                }
                push(#"{"jsonrpc":"2.0","id":\#(id),"result":\#(reply)}"#)
            default: push(#"{"jsonrpc":"2.0","id":\#(id),"result":{}}"#)
        }
    }

    func close() async {
        state.withLock { $0.closed = true }
        continuation.finish()
    }
}

/// The first capture group of `pattern` in `text`, matched in linear time.
private func capture(_ pattern: String, in text: String) -> String? {
    guard let compiled = try? Pattern(pattern), let match = compiled.firstMatch(in: text),
        let range = match.range(ofGroup: 1, in: text)
    else { return nil }
    return String(text[range])
}
