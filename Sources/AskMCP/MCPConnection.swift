internal import AemiJSON
internal import AskAI
internal import Synchronization

/// A client's side of one conversation with one MCP server (ADR-0096): JSON-RPC requests matched to their answers by id, every wait
/// bounded and abandonable, and what the server says unprompted turned into events.
///
/// It is a protocol machine and nothing more. Which servers to connect to, with what rights, and what their tools mean to the model are
/// decided above it; how the bytes travel is decided below it (``MCPTransport``). What it does not assume about a server is what real
/// ones taught: answers come in any order, a server may ignore a cancel, and a server may print what is not a message.
public final class MCPConnection: Sendable {
    /// What a request is waiting for: its answer, or an answer that came before anyone was waiting.
    struct Slot {
        var continuation: CheckedContinuation<Result<JSON, MCPError>, Never>?
        var result: Result<JSON, MCPError>?
        /// When the request times out, as time since the connection was made, and what it asked, for the timeout's error.
        var deadline: Duration?
        var method = ""
    }

    struct State {
        var nextID = 0
        var slots: [Int: Slot] = [:]
        var progress: [String: @Sendable (MCPProgress) -> Void] = [:]
        var begun = false
        var started = false
        var closed = false
        /// The one task that times requests out, and the deadline it sleeps until (roadmap 0114: one timer a connection, not one a request).
        var watchdog: Task<Void, Never>?
        var watchdogTarget: Duration?
        /// Messages waiting their turn while another is being sent, and whether one is.
        var outbox: [[UInt8]] = []
        var sending = false
    }

    /// The most pages of a tool listing that are followed.
    static let maximumListPages = 50

    let transport: any MCPTransport
    let clientName: String
    let clientVersion: String
    let clock: any Clock<Duration>
    let requestTimeout: Duration
    let startTimeout: Duration
    let state = Mutex(State())
    /// Time since the connection was made, on ``clock``: what deadlines are measured in.
    let elapsed: @Sendable () -> Duration
    let eventSink: AsyncStream<MCPEvent>.Continuation

    /// What the server does that is not an answer. Ends with ``MCPEvent/closed``.
    public let events: AsyncStream<MCPEvent>

    /// A connection over `transport`; nothing is sent until ``start()``.
    /// - Parameters:
    ///   - transport: how the bytes travel.
    ///   - clientName: what this client calls itself to the server.
    ///   - clientVersion: its version.
    ///   - clock: what timeouts are measured on.
    ///   - requestTimeout: how long a request may wait for its answer.
    ///   - startTimeout: how long ``start()`` may wait, longer because a server may have to be fetched and launched first.
    public init(
        transport: any MCPTransport, clientName: String, clientVersion: String,
        clock: any Clock<Duration> = ContinuousClock(), requestTimeout: Duration = .seconds(120),
        startTimeout: Duration = .seconds(60)
    ) {
        self.transport = transport
        self.clientName = clientName
        self.clientVersion = clientVersion
        self.clock = clock
        self.requestTimeout = requestTimeout
        self.startTimeout = startTimeout
        elapsed = Self.stopwatch(clock)
        (events, eventSink) = AsyncStream.makeStream(of: MCPEvent.self, bufferingPolicy: .bufferingNewest(256))
    }

    /// A stopwatch on `clock`, started now.
    private static func stopwatch(_ clock: some Clock<Duration>) -> @Sendable () -> Duration {
        let start = clock.now
        return { start.duration(to: clock.now) }
    }

    /// Ends the conversation from this side: whatever waits fails, the transport is closed, and the server is made to leave. Safe to
    /// call again.
    public func close() async {
        shutdown()
        await transport.close()
    }

    /// Marks the connection over and fails everything waiting. Returns whether this call did it.
    @discardableResult
    func shutdown() -> Bool {
        let waiting: [Int]? = state.withLock { state in
            guard !state.closed else { return nil }
            state.closed = true
            state.watchdog?.cancel()
            state.watchdog = nil
            state.outbox.removeAll()
            return Array(state.slots.keys)
        }
        guard let waiting else { return false }
        for id in waiting { resolve(id, .failure(.disconnected)) }
        eventSink.yield(.closed)
        eventSink.finish()
        return true
    }

    /// Gives request `id` its answer, once. Returns whether this call was the one that gave it.
    @discardableResult
    func resolve(_ id: Int, _ result: Result<JSON, MCPError>) -> Bool {
        let delivery = state.withLock { state -> (Bool, CheckedContinuation<Result<JSON, MCPError>, Never>?) in
            guard var slot = state.slots[id], slot.result == nil else { return (false, nil) }
            slot.deadline = nil
            guard let continuation = slot.continuation else {
                slot.result = result
                state.slots[id] = slot
                return (true, nil)
            }
            state.slots[id] = nil
            return (true, continuation)
        }
        delivery.1?.resume(returning: result)
        return delivery.0
    }

    /// Gives up on request `id`: its caller gets `result` now, and the server is told, because it may be working still.
    func abandon(_ id: Int, _ result: Result<JSON, MCPError>, because reason: String) {
        guard resolve(id, result) else { return }
        enqueue(
            MCPWire.notification(
                method: "notifications/cancelled", params: MCPWire.cancelledParams(id: id, reason: reason)))
    }

    /// Queues a message, in order after every one before it, from where nothing can wait: a task is started to send it when nothing else
    /// is sending. Messages queued after the connection closed are dropped.
    func enqueue(_ message: [UInt8]) {
        guard claimSending(message) else { return }
        Task { [self] in await drain(message) }
    }
}
