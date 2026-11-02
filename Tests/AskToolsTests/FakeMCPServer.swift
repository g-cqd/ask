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
        var progress: [String] = []
        var progressAsked = 0
        var resources: Resources?
        var reads: [String] = []
    }
    /// What a server with resources answers: its listing's and templates' items, and a read's contents for a URI.
    struct Resources: Sendable {
        var list: String
        var templates: String
        var read: @Sendable (String) -> String
    }
    private let state: Mutex<State>

    private let destructive: Set<String>
    private let readOnly: Set<String>
    private let harmless: Set<String>

    /// A server with tools of these names, marking `destructive` as the server would (ADR-0111), `readOnly` with `readOnlyHint`, and
    /// `harmless` with `destructiveHint: false`; the others carry no annotations.
    init(tools: [String] = [], destructive: [String] = [], readOnly: [String] = [], harmless: [String] = []) {
        self.destructive = Set(destructive)
        self.readOnly = Set(readOnly)
        self.harmless = Set(harmless)
        (incoming, continuation) = AsyncStream.makeStream(of: [UInt8].self)
        state = Mutex(State(tools: tools))
    }

    var calls: [(name: String, arguments: String)] { state.withLock { $0.calls } }
    var isClosed: Bool { state.withLock { $0.closed } }
    var listings: Int { state.withLock { $0.listings } }
    /// How many calls carried a progress token.
    var progressAsked: Int { state.withLock { $0.progressAsked } }

    func setTools(_ names: [String]) { state.withLock { $0.tools = names } }
    /// The server never answers `initialize`: it is still starting.
    func holdInitialize() { state.withLock { $0.holdsInitialize = true } }
    /// What the transport says about why it failed, as a real one does.
    func diagnose(_ text: String) { state.withLock { $0.diagnosis = text } }
    var diagnostic: String? { state.withLock { $0.diagnosis } }
    func refuseInitialize() { state.withLock { $0.refusesInitialize = true } }
    func reply(to call: @escaping @Sendable (String, String) -> String) { state.withLock { $0.callReply = call } }
    /// Progress sent before each call's reply when the call asks for it: each a notification's fields after its token.
    func reportProgress(_ fields: [String]) { state.withLock { $0.progress = fields } }

    /// The server says it has resources, and answers their listings and reads with these JSON arrays.
    func serveResources(_ resources: Resources) { state.withLock { $0.resources = resources } }
    var readURIs: [String] { state.withLock { $0.reads } }

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
                    let more = state.withLock { $0.resources } == nil ? "" : #","resources":{}"#
                    push(
                        #"{"jsonrpc":"2.0","id":\#(id),"result":{"protocolVersion":"2025-06-18","capabilities":{"tools":{"listChanged":true}\#(more)},"serverInfo":{"name":"fake","version":"1"}}}"#
                    )
                }
            case "tools/list":
                let names = state.withLock { state -> [String] in
                    state.listings += 1
                    return state.tools
                }
                let tools = names.map { name -> String in
                    let marked =
                        destructive.contains(name)
                        ? #","annotations":{"destructiveHint":true}"#
                        : readOnly.contains(name)
                            ? #","annotations":{"readOnlyHint":true}"#
                            : harmless.contains(name) ? #","annotations":{"destructiveHint":false}"# : ""
                    return
                        #"{"name":"\#(name)","description":"does \#(name)","inputSchema":{"type":"object","properties":{"q":{"type":"string"}}}\#(marked)}"#
                }
                push(#"{"jsonrpc":"2.0","id":\#(id),"result":{"tools":[\#(tools.joined(separator: ","))]}}"#)
            case "tools/call":
                let name = capture(#""name":"([^"]+)""#, in: text) ?? ""
                let arguments = capture(#""arguments":(\{[^}]*\})"#, in: text) ?? "{}"
                let (reply, progress) = state.withLock { state -> (String, [String]) in
                    state.calls.append((name, arguments))
                    return (state.callReply(name, arguments), state.progress)
                }
                if let token = capture(#""progressToken":"([^"]+)""#, in: text) {
                    state.withLock { $0.progressAsked += 1 }
                    for fields in progress {
                        push(
                            #"{"jsonrpc":"2.0","method":"notifications/progress","params":{"progressToken":"\#(token)",\#(fields)}}"#
                        )
                    }
                }
                push(#"{"jsonrpc":"2.0","id":\#(id),"result":\#(reply)}"#)
            case "resources/list", "resources/templates/list", "resources/read":
                push(#"{"jsonrpc":"2.0","id":\#(id),"result":\#(resourceReply(method, text))}"#)
            default: push(#"{"jsonrpc":"2.0","id":\#(id),"result":{}}"#)
        }
    }

    private func resourceReply(_ method: String, _ text: String) -> String {
        guard let resources = state.withLock({ $0.resources }) else { return "{}" }
        switch method {
            case "resources/list": return #"{"resources":\#(resources.list)}"#
            case "resources/templates/list": return #"{"resourceTemplates":\#(resources.templates)}"#
            default:
                let uri = capture(#""uri":"([^"]+)""#, in: text) ?? ""
                state.withLock { $0.reads.append(uri) }
                return #"{"contents":\#(resources.read(uri))}"#
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
