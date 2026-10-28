import AskAI
import AskMCP
import Foundation

/// A fake streamable-HTTP server, started as a child and stopped with ``stop()``.
final class HTTPServer {
    let name: String
    let url: URL
    private let process = Process()

    init(name: String, runtime: String, script: String, port: Int, mode: String) throws {
        self.name = name
        url = URL(string: "http://127.0.0.1:\(port)/mcp")!
        process.executableURL = URL(fileURLWithPath: try resolve(runtime))
        process.arguments = [script, String(port), mode]
        let output = Pipe()
        process.standardOutput = output
        try process.run()
        var reader = LineReader(descriptor: output.fileHandleForReading.fileDescriptor)
        guard let line = reader.next(), String(decoding: line, as: UTF8.self).hasPrefix("listening") else {
            throw StressFailure.serverDidNotStart(name)
        }
    }

    func stop() {
        process.terminate()
        process.waitUntilExit()
    }
}

/// `calls` echo calls through ask's HTTP transport and connection.
func httpThroughAsk(_ server: HTTPServer, calls: Int, size: Int, concurrency: Int) async throws -> Duration {
    let transport = try HTTPMCPTransport(url: server.url, userAgent: "stress", http: URLSessionTransport())
    let connection = MCPConnection(transport: transport, clientName: "stress", clientVersion: "1")
    _ = try await connection.start()
    _ = try await callMany(connection, calls: 1, size: size, concurrency: 1)
    let elapsed = try await callMany(connection, calls: calls, size: size, concurrency: concurrency)
    await connection.close()
    return elapsed
}

/// The floor for an HTTP server: the same HTTP stack, one POST a call, the body collected and parsed once.
func httpFloor(_ server: HTTPServer, calls: Int, size: Int, sse: Bool) async throws -> Duration {
    let http = URLSessionTransport()
    let headers: [(name: String, value: String)] = [
        ("content-type", "application/json"), ("accept", "application/json, text/event-stream"),
        ("mcp-protocol-version", "2025-06-18"), ("mcp-session-id", "s1")
    ]
    func call(_ id: Int) async throws -> Int {
        let response = try await http.send(
            HTTPRequest(url: server.url, method: "POST", headers: headers, body: Payloads.request(id: id, size: size)))
        var body = try await response.collect(limit: 64 << 20)
        if sse, let start = body.firstIndex(of: UInt8(ascii: "{")) {
            body = Array(body[start...])
            while let last = body.last, last == 10 { body.removeLast() }
        }
        return Payloads.text(of: body)?.utf8.count ?? -1_000_000
    }
    _ = try await call(1)
    var total = 0
    let elapsed = try await ContinuousClock()
        .measure {
            for id in 2 ..< (2 + calls) { total &+= try await call(id) }
        }
    guard total == calls * size else { throw StressFailure.wrongAnswer }
    return elapsed
}
