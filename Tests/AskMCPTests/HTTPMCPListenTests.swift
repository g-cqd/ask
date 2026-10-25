internal import AskAI
internal import Foundation
internal import Testing

@testable import AskMCP

/// The server's own stream, the GET of the streamable HTTP transport (ADR-0108): opened after the handshake, ignored when the server
/// has none, cancelled when the conversation closes, and carrying the messages a server sends unprompted.
@Suite("The client listens on the server's stream, and what it hears arrives", .timeLimit(.minutes(1)))
struct HTTPMCPListenTests {
    private func transport(_ http: ScriptedHTTP) throws -> HTTPMCPTransport {
        try HTTPMCP.transport(http)
    }

    @Test func `the stream is asked for once the version is agreed, with the session and the version named`()
        async throws
    {
        let http = ScriptedHTTP { seen in
            seen.method == "GET" ? ScriptedHTTP.status(405) : ScriptedHTTP.status(202)
        }
        let transport = try transport(http)
        _ = try await HTTPMCP.send(HTTPMCP.ping, on: transport)
        transport.negotiated(protocolVersion: "2025-06-18")
        await http.waitForRequests(2)
        let gets = http.requests.filter { $0.method == "GET" }
        #expect(gets.count == 1, "asked once")
        guard let get = gets.first else { return }
        #expect(get.headers["accept"] == "text/event-stream")
        #expect(get.headers["user-agent"] == "ask-test/1")
        #expect(get.headers["content-type"] == nil)
        await transport.close()
    }

    @Test func `a server with no stream is not a problem, and nothing more is asked of it`() async throws {
        let http = ScriptedHTTP { seen in
            seen.method == "GET"
                ? ScriptedHTTP.status(405) : ScriptedHTTP.json(#"{"jsonrpc":"2.0","id":7,"result":{}}"#)
        }
        let transport = try transport(http)
        var incoming = transport.incoming.makeAsyncIterator()
        try await HTTPMCP.send(HTTPMCP.ping, on: transport)
        transport.negotiated(protocolVersion: "2025-06-18")
        #expect(await HTTPMCP.next(&incoming)?.contains(#""result""#) == true, "the conversation goes on as before")
        await transport.close()
        #expect(http.requests.count == 2, "one GET, asked once, not again after the 405")
    }

    @Test func `what the server says unprompted arrives, and a changed tool list reaches the connection`() async throws
    {
        let (opened, openedSink) = AsyncStream.makeStream(of: Void.self)
        let (say, saySink) = AsyncStream.makeStream(of: Void.self)
        let http = ScriptedHTTP { seen in
            if seen.method == "GET" {
                let (reply, stream) = ScriptedHTTP.held {}
                Task {
                    openedSink.yield()
                    for await _ in say {
                        stream.yield(
                            Array(
                                "event: message\ndata: {\"jsonrpc\":\"2.0\",\"method\":\"notifications/tools/list_changed\"}\n\n"
                                    .utf8))
                    }
                    stream.finish()
                }
                return reply
            }
            return ScriptedHTTP.status(202)
        }
        let transport = try transport(http)
        var incoming = transport.incoming.makeAsyncIterator()
        transport.negotiated(protocolVersion: "2025-06-18")
        var opening = opened.makeAsyncIterator()
        _ = await opening.next()
        saySink.yield()
        #expect(await HTTPMCP.next(&incoming)?.contains("tools/list_changed") == true)
        saySink.finish()
        await transport.close()
    }

    @Test func `a stream that ends on its own is not a failure, and the conversation goes on`() async throws {
        let http = ScriptedHTTP { seen in
            seen.method == "GET"
                ? ScriptedHTTP.events([
                    "data: {\"jsonrpc\":\"2.0\",\"method\":\"notifications/message\",\"params\":{}}\n\n"
                ])
                : ScriptedHTTP.json(#"{"jsonrpc":"2.0","id":7,"result":{}}"#)
        }
        let transport = try transport(http)
        var incoming = transport.incoming.makeAsyncIterator()
        transport.negotiated(protocolVersion: "2025-06-18")
        #expect(await HTTPMCP.next(&incoming)?.contains("notifications/message") == true)
        try await HTTPMCP.send(HTTPMCP.ping, on: transport)
        #expect(
            await HTTPMCP.next(&incoming)?.contains(#""result""#) == true, "a POST still works after the stream ended")
        await transport.close()
    }

    @Test func `closing stops listening`() async throws {
        let (ended, endedSink) = AsyncStream.makeStream(of: Void.self)
        let http = ScriptedHTTP { seen in
            seen.method == "GET" ? ScriptedHTTP.held { endedSink.yield() }.0 : ScriptedHTTP.status(202)
        }
        let transport = try transport(http)
        transport.negotiated(protocolVersion: "2025-06-18")
        await http.waitForRequests(1)
        await transport.close()
        var iterator = ended.makeAsyncIterator()
        #expect(await iterator.next() != nil, "the stream the server held was let go")
    }

    @Test func `a negotiation after the close starts no stream`() async throws {
        let http = ScriptedHTTP { _ in ScriptedHTTP.status(405) }
        let transport = try transport(http)
        await transport.close()
        transport.negotiated(protocolVersion: "2025-06-18")
        #expect(http.requests.isEmpty)
    }
}
