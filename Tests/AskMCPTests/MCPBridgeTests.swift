internal import AemiMCP
internal import AskAI
internal import Foundation
internal import Synchronization
internal import Testing

@testable import AskMCP

/// The glue between ask's seams and AemiMCP, whose own tests cover the client (they moved there with it).
struct MCPBridgeTests {
    private final class Recorder: HTTPTransport {
        let seen = Mutex<[HTTPRequest]>([])

        func send(_ request: HTTPRequest) async throws -> HTTPStreamingResponse {
            seen.withLock { $0.append(request) }
            return HTTPStreamingResponse(
                status: 207,
                headers: ["mcp-session-id": "s-1"],
                body: AsyncThrowingStream { continuation in
                    continuation.yield(Array("abc".utf8))
                    continuation.finish()
                }
            )
        }
    }

    @Test func `a request and its reply pass through the bridge unchanged`() async throws {
        let recorder = Recorder()
        let url = try #require(URL(string: "https://example.com/mcp"))
        let request = MCPHTTPRequest(
            url: url,
            method: "POST",
            headers: [("Accept", "text/event-stream"), ("Mcp-Session-Id", "s-0")],
            body: Array("{}".utf8),
            allowsRedirects: false
        )
        let reply = try await MCPHTTPBridge(recorder).send(request)
        let sent = try #require(recorder.seen.withLock { $0.first })
        #expect(sent.url == url && sent.method == "POST" && sent.body == Array("{}".utf8) && !sent.allowsRedirects)
        #expect(sent.headers.map(\.name) == ["Accept", "Mcp-Session-Id"])
        #expect(sent.headers.map(\.value) == ["text/event-stream", "s-0"])
        #expect(reply.status == 207 && reply.headers["mcp-session-id"] == "s-1")
        #expect(try await reply.collect(limit: 16) == Array("abc".utf8))
    }

    @Test func `JSON objects convert both ways with their bytes kept`() throws {
        let schema = try MCPJSONObject(
            validating: Array(#"{"type":"object","properties":{"a":{"type":"string"}}}"#.utf8)
        )
        let forModel = try #require(JSONObject(schema))
        #expect(forModel.bytes == schema.bytes)
        let back = try #require(MCPJSONObject(forModel))
        #expect(back == schema)
    }
}
