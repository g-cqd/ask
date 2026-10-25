internal import AskAI
internal import Foundation
internal import Testing

@testable import AskMCP

/// What the HTTP transport makes of each reply (ADR-0096): JSON, a batch, events, nothing, and every way a reply can go wrong.
@Suite(
    "An HTTP transport turns each kind of reply into messages, and each failure into an answer", .timeLimit(.minutes(1))
)
struct HTTPMCPReplyTests {
    @Test func `a JSON reply is one message`() async throws {
        let reply = #"{"jsonrpc":"2.0","id":7,"result":{}}"#
        let http = ScriptedHTTP { _ in ScriptedHTTP.json(reply) }
        let transport = try HTTPMCP.transport(http)
        var incoming = transport.incoming.makeAsyncIterator()
        try await HTTPMCP.send(HTTPMCP.ping, on: transport)
        #expect(await HTTPMCP.next(&incoming) == reply)
        await transport.close()
    }

    @Test func `a batch in a JSON reply is each of its messages, in order`() async throws {
        let http = ScriptedHTTP { _ in
            ScriptedHTTP.json(#"[{"jsonrpc":"2.0","method":"a"}, {"jsonrpc":"2.0","id":7,"result":{}}]"#)
        }
        let transport = try HTTPMCP.transport(http)
        var incoming = transport.incoming.makeAsyncIterator()
        try await HTTPMCP.send(HTTPMCP.ping, on: transport)
        #expect(await HTTPMCP.next(&incoming)?.contains(#""method":"a""#) == true)
        #expect(await HTTPMCP.next(&incoming)?.contains(#""id":7"#) == true)
        await transport.close()
    }

    @Test func `an event stream is its messages, however the network cut it`() async throws {
        let first = #"{"jsonrpc":"2.0","method":"notifications/progress","params":{"progressToken":"t","progress":1}}"#
        let second = #"{"jsonrpc":"2.0","id":7,"result":{}}"#
        let http = ScriptedHTTP { _ in
            ScriptedHTTP.events([
                "event: message\ndata: " + first.prefix(20), String(first.dropFirst(20)) + "\n\n",
                "data: \(second)\r\n\r\n"
            ])
        }
        let transport = try HTTPMCP.transport(http)
        var incoming = transport.incoming.makeAsyncIterator()
        try await HTTPMCP.send(HTTPMCP.ping, on: transport)
        #expect(await HTTPMCP.next(&incoming) == first)
        #expect(await HTTPMCP.next(&incoming) == second)
        await transport.close()
    }

    @Test func `an event that is not a message is ignored`() async throws {
        let answer = #"{"jsonrpc":"2.0","id":7,"result":{}}"#
        let http = ScriptedHTTP { _ in ScriptedHTTP.events(["event: endpoint\ndata: /elsewhere\n\ndata: \(answer)\n\n"])
        }
        let transport = try HTTPMCP.transport(http)
        var incoming = transport.incoming.makeAsyncIterator()
        try await HTTPMCP.send(HTTPMCP.ping, on: transport)
        #expect(await HTTPMCP.next(&incoming) == answer)
        await transport.close()
    }

    @Test func `an accepted notification is not answered, and a request after it still works`() async throws {
        let http = ScriptedHTTP { seen in
            seen.rpcMethod == "ping"
                ? ScriptedHTTP.json(#"{"jsonrpc":"2.0","id":7,"result":{}}"#) : ScriptedHTTP.status(202)
        }
        let transport = try HTTPMCP.transport(http)
        var incoming = transport.incoming.makeAsyncIterator()
        try await HTTPMCP.send(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#, on: transport)
        try await HTTPMCP.send(HTTPMCP.ping, on: transport)
        #expect(
            await HTTPMCP.next(&incoming)?.contains(#""id":7"#) == true,
            "the first thing delivered is the answer to the ping")
        await transport.close()
    }

    @Test func `a request that gets an HTTP error is answered with an error carrying its id and the status`()
        async throws
    {
        let http = ScriptedHTTP { _ in ScriptedHTTP.chunks(500, ["upstream exploded"]) }
        let transport = try HTTPMCP.transport(http)
        var incoming = transport.incoming.makeAsyncIterator()
        try await HTTPMCP.send(HTTPMCP.ping, on: transport)
        guard
            case .response(let id, .failure(.rpc(_, let message))) = MCPEnvelope.parse(
                Array((await HTTPMCP.next(&incoming) ?? "").utf8))
        else {
            Issue.record("not an error answer")
            return
        }
        #expect(id == 7 && message.contains("500") && message.contains("upstream exploded"))
        await transport.close()
    }

    @Test func `a notification that gets an HTTP error says nothing, because nothing is waiting`() async throws {
        let http = ScriptedHTTP { seen in
            seen.rpcMethod == "ping"
                ? ScriptedHTTP.json(#"{"jsonrpc":"2.0","id":7,"result":{}}"#) : ScriptedHTTP.chunks(500, [])
        }
        let transport = try HTTPMCP.transport(http)
        var incoming = transport.incoming.makeAsyncIterator()
        try await HTTPMCP.send(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#, on: transport)
        try await HTTPMCP.send(HTTPMCP.ping, on: transport)
        #expect(await HTTPMCP.next(&incoming)?.contains(#""result""#) == true)
        await transport.close()
    }

    @Test func `a reply that never answers the request is an error, not a wait for the timeout`() async throws {
        let http = ScriptedHTTP { _ in
            ScriptedHTTP.events([
                #"data: {"jsonrpc":"2.0","method":"notifications/message","params":{"level":"info","data":"x"}}"#
                    + "\n\n"
            ])
        }
        let transport = try HTTPMCP.transport(http)
        var incoming = transport.incoming.makeAsyncIterator()
        try await HTTPMCP.send(HTTPMCP.ping, on: transport)
        #expect(await HTTPMCP.next(&incoming)?.contains("notifications/message") == true)
        guard
            case .response(7, .failure(.rpc(_, let message))) = MCPEnvelope.parse(
                Array((await HTTPMCP.next(&incoming) ?? "").utf8))
        else {
            Issue.record("no error for the unanswered request")
            return
        }
        #expect(message.contains("without answering"))
        await transport.close()
    }

    @Test func `an answer to some other request does not count as the answer to this one`() async throws {
        let http = ScriptedHTTP { _ in ScriptedHTTP.json(#"{"jsonrpc":"2.0","id":99,"result":{}}"#) }
        let transport = try HTTPMCP.transport(http)
        var incoming = transport.incoming.makeAsyncIterator()
        try await HTTPMCP.send(HTTPMCP.ping, on: transport)
        #expect(await HTTPMCP.next(&incoming)?.contains(#""id":99"#) == true)
        guard case .response(7, .failure(.rpc)) = MCPEnvelope.parse(Array((await HTTPMCP.next(&incoming) ?? "").utf8))
        else {
            Issue.record("no error for the request that went unanswered")
            return
        }
        await transport.close()
    }

    @Test func `a reply of some other kind is an error`() async throws {
        let http = ScriptedHTTP { _ in ScriptedHTTP.chunks(200, ["<html>"], headers: ["content-type": "text/html"]) }
        let transport = try HTTPMCP.transport(http)
        var incoming = transport.incoming.makeAsyncIterator()
        try await HTTPMCP.send(HTTPMCP.ping, on: transport)
        let text = await HTTPMCP.next(&incoming) ?? ""
        #expect(text.contains("text/html") && text.contains(#""id":7"#))
        await transport.close()
    }
}
