internal import AskAI
internal import Foundation
internal import Testing

@testable import AskMCP

/// A reply's stream that ends before its answer is resumed (MCP 2025-11-25, Streamable HTTP, "Resumability and redelivery"; the
/// conformance suite's `sse-retry`): after the server's `retry` wait, a GET carrying `Last-Event-ID`, whose events bring the answer.
@Suite("An HTTP transport resumes a reply's stream that ended early", .timeLimit(.minutes(1)))
struct HTTPMCPResumeTests {
    @Test func `the decoder keeps the last event id and the retry wait`() throws {
        var decoder = SSEDecoder(limits: .init(maximumEventBytes: 1024))
        var events: [SSEEvent] = []
        let stream = Array("id: e-1\nretry: 250\ndata: {}\n\nid: e-2\ndata: x\n\nretry: nope\n\n".utf8)
        try stream.withUnsafeBufferPointer { try decoder.feed($0.span, into: &events) }
        #expect(events.count == 2)
        #expect(decoder.lastEventID == "e-2")
        #expect(decoder.retry == .milliseconds(250), "a retry that is not digits is ignored")
    }

    @Test func `a stream that ends unanswered is resumed with Last-Event-ID after its retry`() async throws {
        let answer = #"{"jsonrpc":"2.0","id":7,"result":{}}"#
        let http = ScriptedHTTP { seen in
            if seen.method == "GET", seen.headers["last-event-id"] == "e-2" {
                return ScriptedHTTP.events(["id: e-3\ndata: \(answer)\n\n"])
            }
            if seen.method == "GET" { return ScriptedHTTP.status(405) }
            return ScriptedHTTP.events(["id: e-2\nretry: 5\ndata: \n\n"])
        }
        let transport = try HTTPMCP.transport(http)
        var incoming = transport.incoming.makeAsyncIterator()
        try await HTTPMCP.send(HTTPMCP.ping, on: transport)
        #expect(await HTTPMCP.next(&incoming) == answer)
        let resumed = http.requests.filter { $0.headers["last-event-id"] != nil }
        #expect(resumed.count == 1)
        #expect(resumed.first?.headers["accept"] == "text/event-stream")
        await transport.close()
    }

    @Test func `a stream without event ids that ends unanswered fails at once`() async throws {
        let http = ScriptedHTTP { seen in
            seen.method == "GET" ? ScriptedHTTP.status(405) : ScriptedHTTP.events([": nothing\n\n"])
        }
        let transport = try HTTPMCP.transport(http)
        var incoming = transport.incoming.makeAsyncIterator()
        try await HTTPMCP.send(HTTPMCP.ping, on: transport)
        #expect(await HTTPMCP.next(&incoming)?.contains("ended its reply without answering") == true)
        #expect(http.requests.allSatisfy { $0.headers["last-event-id"] == nil })
        await transport.close()
    }
}
