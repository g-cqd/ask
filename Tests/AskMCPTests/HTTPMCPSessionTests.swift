internal import AemiRegex
internal import AskAI
internal import Foundation
internal import Testing

@testable import AskMCP

/// What the HTTP transport remembers and sends: the session and version headers, concurrency, closing, and where a credential may go.
@Suite(
    "An HTTP transport keeps a session, names itself, ends politely and protects a credential", .timeLimit(.minutes(1)))
struct HTTPMCPSessionTests {
    @Test func `a request is a POST that says what it sends, what it accepts, and who is asking`() async throws {
        let http = ScriptedHTTP { _ in ScriptedHTTP.status(202) }
        let transport = try HTTPMCP.transport(http, headers: [(name: "Authorization", value: "Bearer t")])
        try await HTTPMCP.send(HTTPMCP.ping, on: transport)
        await http.waitForRequests(1)
        let seen = http.requests[0]
        #expect(seen.method == "POST" && seen.body == HTTPMCP.ping)
        #expect(seen.headers["content-type"] == "application/json")
        #expect(seen.headers["accept"] == "application/json, text/event-stream")
        #expect(seen.headers["user-agent"] == "ask-test/1")
        #expect(seen.headers["authorization"] == "Bearer t")
        #expect(seen.headers["mcp-session-id"] == nil && seen.headers["mcp-protocol-version"] == nil)
        await transport.close()
    }

    @Test func `a server that sends a session id is sent it back, and told the version once one is agreed`()
        async throws
    {
        let http = ScriptedHTTP { seen in
            seen.rpcMethod == "initialize"
                ? ScriptedHTTP.json(#"{"jsonrpc":"2.0","id":1,"result":{}}"#, headers: ["mcp-session-id": "abc-123"])
                : ScriptedHTTP.status(202)
        }
        let transport = try HTTPMCP.transport(http)
        var incoming = transport.incoming.makeAsyncIterator()
        try await HTTPMCP.send(#"{"jsonrpc":"2.0","id":1,"method":"initialize"}"#, on: transport)
        _ = await HTTPMCP.next(&incoming)
        transport.negotiated(protocolVersion: "2025-06-18")
        try await HTTPMCP.send(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#, on: transport)
        await http.waitForRequests(2)
        #expect(http.requests[1].headers["mcp-session-id"] == "abc-123")
        #expect(http.requests[1].headers["mcp-protocol-version"] == "2025-06-18")
        await transport.close()
    }

    @Test func `a session the server has forgotten ends the conversation`() async throws {
        let http = ScriptedHTTP { seen in
            seen.headers["mcp-session-id"] == nil
                ? ScriptedHTTP.json(#"{"jsonrpc":"2.0","id":1,"result":{}}"#, headers: ["mcp-session-id": "s"])
                : ScriptedHTTP.chunks(404, [])
        }
        let transport = try HTTPMCP.transport(http)
        var incoming = transport.incoming.makeAsyncIterator()
        try await HTTPMCP.send(#"{"jsonrpc":"2.0","id":1,"method":"initialize"}"#, on: transport)
        _ = await HTTPMCP.next(&incoming)
        try await HTTPMCP.send(HTTPMCP.ping, on: transport)
        #expect(
            await HTTPMCP.next(&incoming) == nil,
            "the stream ends, which is how the connection learns the server is gone")
        await transport.close()
    }

    @Test func `a slow reply does not hold up the next request`() async throws {
        let (gate, release) = AsyncStream.makeStream(of: Void.self)
        let http = ScriptedHTTP { seen in
            if seen.body.contains(#""id":7"#) {
                for await _ in gate { break }
                return ScriptedHTTP.json(#"{"jsonrpc":"2.0","id":7,"result":{}}"#)
            }
            return ScriptedHTTP.json(#"{"jsonrpc":"2.0","id":8,"result":{}}"#)
        }
        let transport = try HTTPMCP.transport(http)
        var incoming = transport.incoming.makeAsyncIterator()
        try await HTTPMCP.send(HTTPMCP.ping, on: transport)
        try await HTTPMCP.send(#"{"jsonrpc":"2.0","id":8,"method":"ping"}"#, on: transport)
        #expect(
            await HTTPMCP.next(&incoming)?.contains(#""id":8"#) == true,
            "the second is answered while the first is still waiting")
        release.yield()
        #expect(await HTTPMCP.next(&incoming)?.contains(#""id":7"#) == true)
        await transport.close()
    }

    @Test func `closing ends the session at the server, and a server that refuses that is not a problem`() async throws
    {
        let http = ScriptedHTTP { seen in
            seen.method == "DELETE"
                ? ScriptedHTTP.status(405)
                : ScriptedHTTP.json(#"{"jsonrpc":"2.0","id":1,"result":{}}"#, headers: ["mcp-session-id": "s-1"])
        }
        let transport = try HTTPMCP.transport(http)
        var incoming = transport.incoming.makeAsyncIterator()
        try await HTTPMCP.send(#"{"jsonrpc":"2.0","id":1,"method":"initialize"}"#, on: transport)
        _ = await HTTPMCP.next(&incoming)
        await transport.close()
        let delete = http.requests.last
        #expect(delete?.method == "DELETE" && delete?.headers["mcp-session-id"] == "s-1")
        #expect(await HTTPMCP.next(&incoming) == nil)
    }

    @Test func `closing a conversation that never had a session sends nothing`() async throws {
        let http = ScriptedHTTP()
        let transport = try HTTPMCP.transport(http)
        await transport.close()
        #expect(http.requests.isEmpty)
    }

    @Test func `nothing is sent after the close`() async throws {
        let http = ScriptedHTTP()
        let transport = try HTTPMCP.transport(http)
        await transport.close()
        await #expect(throws: (any Error).self) { try await HTTPMCP.send(HTTPMCP.ping, on: transport) }
        #expect(http.requests.isEmpty)
    }

    @Test func `a credential does not travel in the clear to another machine`() throws {
        let insecure = URL(string: "http://example.test/mcp")!
        #expect(throws: MCPError.self) {
            _ = try HTTPMCP.transport(
                ScriptedHTTP(), url: insecure, headers: [(name: "Authorization", value: "Bearer t")])
        }
        _ = try HTTPMCP.transport(ScriptedHTTP(), url: insecure)
        _ = try HTTPMCP.transport(
            ScriptedHTTP(), url: URL(string: "http://localhost:8080/mcp")!,
            headers: [(name: "Authorization", value: "Bearer t")])
    }

    @Test func `a whole conversation through a connection: start, list, call`() async throws {
        let http = ScriptedHTTP { seen in
            let id = capture(#""id":(\d+)"#, in: seen.body) ?? "0"
            switch seen.rpcMethod {
                case "initialize":
                    return ScriptedHTTP.json(
                        #"{"jsonrpc":"2.0","id":\#(id),"result":{"protocolVersion":"2025-06-18","capabilities":{"tools":{}},"serverInfo":{"name":"web","version":"1"}}}"#,
                        headers: ["mcp-session-id": "s"])
                case "tools/list":
                    return ScriptedHTTP.events([
                        #"data: {"jsonrpc":"2.0","id":\#(id),"result":{"tools":[{"name":"t","inputSchema":{"type":"object"}}]}}"#
                            + "\n\n"
                    ])
                case "tools/call":
                    return ScriptedHTTP.json(
                        #"{"jsonrpc":"2.0","id":\#(id),"result":{"content":[{"type":"text","text":"ok"}]}}"#)
                default: return ScriptedHTTP.status(202)
            }
        }
        let connection = MCPConnection(transport: try HTTPMCP.transport(http), clientName: "ask", clientVersion: "1")
        #expect(try await connection.start().name == "web")
        #expect(try await connection.listTools().map(\.name) == ["t"])
        #expect(try await connection.callTool("t", arguments: .empty).content == [.text("ok")])
        await connection.close()
        let later = http.requests.filter { $0.rpcMethod == "tools/call" }
        #expect(
            later.first?.headers["mcp-session-id"] == "s"
                && later.first?.headers["mcp-protocol-version"] == "2025-06-18")
        #expect(http.requests.last?.method == "DELETE")
    }
}

/// The first capture group of `pattern` in `text`, matched in linear time.
private func capture(_ pattern: String, in text: String) -> String? {
    guard let compiled = try? Pattern(pattern), let match = compiled.firstMatch(in: text),
        let range = match.range(ofGroup: 1, in: text)
    else { return nil }
    return String(text[range])
}
