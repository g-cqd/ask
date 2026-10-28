import AskMCP

/// A server inside the process that answers at once, so what is measured is the connection: ids, waiting, framing and parsing.
///
/// It reads only the id, with a byte scan, and answers request 1 (the connection's `initialize`) with a handshake and every other request with
/// the same echo. Its own cost is measured apart, by ``serverCost(calls:size:)``.
final class LoopbackServer: MCPTransport {
    let incoming: AsyncStream<[UInt8]>
    private let sink: AsyncStream<[UInt8]>.Continuation
    private let prefix = Array(#"{"jsonrpc":"2.0","id":"#.utf8)
    private let suffix: [UInt8]
    private static let handshake = Array(
        #"{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-06-18","capabilities":{"tools":{}},"serverInfo":{"name":"loop","version":"1"}}}"#
            .utf8)

    init(size: Int) {
        (incoming, sink) = AsyncStream.makeStream(of: [UInt8].self)
        suffix = Array((#","result":"# + Payloads.result(size: size) + "}").utf8)
    }

    func send(_ message: [UInt8]) async throws {
        if let reply = answer(message) { sink.yield(reply) }
    }

    func close() async { sink.finish() }

    /// The answer to `message`, or nil for a notification.
    func answer(_ message: [UInt8]) -> [UInt8]? {
        guard let id = Self.id(in: message) else { return nil }
        if id.elementsEqual([UInt8(ascii: "1")]) { return Self.handshake }
        return prefix + id + suffix
    }

    /// The digits after `"id":`, or nil when there is none.
    static func id(in message: [UInt8]) -> ArraySlice<UInt8>? {
        let key = Array(#""id":"#.utf8)
        guard message.count > key.count else { return nil }
        for start in 0 ... (message.count - key.count) where message[start] == key[0] {
            guard message[start ..< start + key.count].elementsEqual(key) else { continue }
            var end = start + key.count
            while end < message.count, (48 ... 57).contains(message[end]) { end += 1 }
            return message[(start + key.count) ..< end]
        }
        return nil
    }
}

/// What the loopback server itself costs a call, to tell it apart from the connection's cost.
func serverCost(calls: Int, size: Int) -> Duration {
    let server = LoopbackServer(size: size)
    let request = Payloads.request(id: 4242, size: size)
    var total = 0
    let elapsed = ContinuousClock()
        .measure {
            for _ in 0 ..< calls { total &+= server.answer(request)?.count ?? 0 }
        }
    keep(total)
    return elapsed
}

/// `calls` tool calls over a connection to the loopback server, `concurrency` of them in flight at once.
func loopback(calls: Int, size: Int, concurrency: Int) async throws -> Duration {
    let connection = MCPConnection(transport: LoopbackServer(size: size), clientName: "stress", clientVersion: "1")
    _ = try await connection.start()
    let elapsed = try await callMany(connection, calls: calls, size: size, concurrency: concurrency)
    await connection.close()
    return elapsed
}
