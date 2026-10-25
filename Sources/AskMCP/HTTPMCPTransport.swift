public import AskAI
public import Foundation
internal import Synchronization

/// A server that is a URL, spoken to by POST (the protocol's streamable HTTP transport, ADR-0096).
///
/// Each message the connection sends is a request of its own, made at once and not queued behind the others: a tool that takes a minute
/// must not hold up the cancel that follows it. Whatever comes back, a JSON message, a batch, or a stream of events, is delivered as
/// messages. A request that cannot be answered, because the server errs or ends its reply without answering, is answered here with an
/// error carrying its id, so the caller learns now and not at its timeout.
///
/// Not done: the optional GET stream on which a server speaks unprompted, so changes to the tool list reach a caller only on a reply
/// stream. A session the server forgets ends the conversation; a new one is the caller's to open.
public final class HTTPMCPTransport: MCPTransport {
    /// What changes while the conversation runs.
    struct State {
        var sessionID: String?
        var protocolVersion: String?
        var closed = false
        var tasks: [Int: Task<Void, Never>] = [:]
        var finishedEarly: Set<Int> = []
        var nextTask = 0
    }

    /// The code of the errors this transport makes up. JSON-RPC leaves -32000…-32099 to implementations.
    static let failureCode = -32000
    /// The most bytes of a JSON reply or of one event.
    static let maximumMessageBytes = 64 << 20

    public let incoming: AsyncStream<[UInt8]>
    let sink: AsyncStream<[UInt8]>.Continuation
    let url: URL
    let headers: [(name: String, value: String)]
    let userAgent: String
    let http: any HTTPTransport
    let clock: any Clock<Duration>
    let grace: Duration
    let state = Mutex(State())

    /// A transport to `url`.
    /// - Parameters:
    ///   - url: the server's endpoint.
    ///   - headers: sent with every request; this is where a credential goes.
    ///   - userAgent: who is asking; some servers' front doors refuse a client that names none.
    ///   - http: how requests are made.
    ///   - clock: what the grace is measured on.
    ///   - grace: how long closing may wait for the server to end its session.
    /// - Throws: ``MCPError/refusedEndpoint(_:)`` if a credential would cross the network unencrypted (ADR-0024).
    public init(
        url: URL, headers: [(name: String, value: String)] = [], userAgent: String, http: any HTTPTransport,
        clock: any Clock<Duration> = ContinuousClock(), grace: Duration = .seconds(2)
    ) throws(MCPError) {
        if let refusal = EndpointPolicy.refusal(for: url, carriesCredential: !headers.isEmpty) {
            throw .refusedEndpoint(refusal)
        }
        (incoming, sink) = AsyncStream.makeStream(of: [UInt8].self)
        self.url = url
        self.headers = headers
        self.userAgent = userAgent
        self.http = http
        self.clock = clock
        self.grace = grace
    }

    public func negotiated(protocolVersion: String) {
        state.withLock { $0.protocolVersion = protocolVersion }
    }

    public func send(_ message: [UInt8]) async throws {
        let request = Self.requestID(of: message)
        let key: Int? = state.withLock { state in
            guard !state.closed else { return nil }
            state.nextTask += 1
            return state.nextTask
        }
        guard let key else { throw CancellationError() }
        let task = Task { [self] in
            await exchange(message, requestID: request)
            state.withLock { state in
                if state.tasks.removeValue(forKey: key) == nil { state.finishedEarly.insert(key) }
            }
        }
        state.withLock { state in
            if state.finishedEarly.remove(key) == nil { state.tasks[key] = task }
        }
    }

    public func close() async {
        let (tasks, session) = state.withLock { state -> ([Task<Void, Never>], String?) in
            guard !state.closed else { return ([], nil) }
            state.closed = true
            defer { state.tasks = [:] }
            return (Array(state.tasks.values), state.sessionID)
        }
        for task in tasks { task.cancel() }
        if let session { await endSession(session) }
        sink.finish()
    }

    /// The id of `message` if it is a request, which is a message somebody is waiting to hear about.
    static func requestID(of message: [UInt8]) -> Int? {
        guard case .request(let id, _, _) = MCPEnvelope.parse(message) else { return nil }
        return Int(String(decoding: id, as: UTF8.self))
    }
}
