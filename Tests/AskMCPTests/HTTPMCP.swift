internal import AskAI
internal import Foundation

@testable import AskMCP

/// What the HTTP transport's suites share: a transport on a played server, and sending and receiving without ceremony.
enum HTTPMCP {
    static let url = URL(string: "https://example.test/mcp")!
    static let ping = #"{"jsonrpc":"2.0","id":7,"method":"ping"}"#

    /// A transport to `url` through `http`, naming itself `ask-test/1`.
    static func transport(
        _ http: ScriptedHTTP, url: URL = HTTPMCP.url, headers: [(name: String, value: String)] = []
    ) throws -> HTTPMCPTransport {
        try HTTPMCPTransport(url: url, headers: headers, userAgent: "ask-test/1", http: http)
    }

    /// Sends `text` as a message.
    static func send(_ text: String, on transport: HTTPMCPTransport) async throws {
        try await transport.send(Array(text.utf8))
    }

    /// The next message the server sent, as text, or nil when the stream ended.
    static func next(_ iterator: inout AsyncStream<[UInt8]>.AsyncIterator) async -> String? {
        await iterator.next().map { String(decoding: $0, as: UTF8.self) }
    }
}
