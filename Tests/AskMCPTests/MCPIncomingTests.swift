internal import AemiJSON
internal import AskAI
internal import Foundation
internal import Synchronization
internal import Testing

@testable import AskMCP

/// What a server sends that the client did not ask for: requests (it declared no capabilities, so only `ping` is expected),
/// notifications about tools, progress and logs, and lines that are not messages at all.
@Suite("A connection answers what it must, ignores what it can, and reports what matters", .timeLimit(.minutes(1)))
struct MCPIncomingTests {
    private static let initResult =
        #"{"protocolVersion":"2025-11-25","capabilities":{"tools":{"listChanged":true}},"serverInfo":{"name":"s","version":"1"}}"#

    private func started() async throws -> (MCPConnection, ScriptedTransport) {
        let transport = ScriptedTransport()
        transport.on("initialize") { [$0.result(Self.initResult)] }
        let connection = MCPConnection(transport: transport, clientName: "ask", clientVersion: "1")
        _ = try await connection.start()
        return (connection, transport)
    }

    private func reply(to id: String, in transport: ScriptedTransport) async throws -> String {
        // The reply is a message with no method; wait until the client has written one.
        await transport.waitUntilSentReply()
        return try #require(transport.sent.last { $0.method == nil }?.line, "no reply for \(id)")
    }

    @Test func `a ping from the server is answered with an empty result carrying the server's own id`() async throws {
        let (_, transport) = try await started()
        transport.push(#"{"jsonrpc":"2.0","id":"srv-1","method":"ping"}"#)
        let line = try await reply(to: "srv-1", in: transport)
        let root = try AemiJSON.parse(Array(line.utf8)).root
        #expect(root["id"].string == "srv-1" && root["result"].isObject && !root["error"].isObject)
    }

    @Test func `a request the client has no capability for is refused as unknown, with the server's id`() async throws {
        let (_, transport) = try await started()
        transport.push(#"{"jsonrpc":"2.0","id":41,"method":"sampling/createMessage","params":{}}"#)
        let line = try await reply(to: "41", in: transport)
        let root = try AemiJSON.parse(Array(line.utf8)).root
        #expect(root["id"].int == 41 && root["error"]["code"].int == -32601)
    }

    @Test func `a list-changed notice is an event, so the caller can list again`() async throws {
        let (connection, transport) = try await started()
        var events = connection.events.makeAsyncIterator()
        transport.push(#"{"jsonrpc":"2.0","method":"notifications/tools/list_changed"}"#)
        #expect(await events.next() == .toolsChanged)
    }

    @Test func `a log message is an event with its level and its text, whatever shape the text is`() async throws {
        let (connection, transport) = try await started()
        var events = connection.events.makeAsyncIterator()
        transport.push(
            #"{"jsonrpc":"2.0","method":"notifications/message","params":{"level":"warning","logger":"x","data":"disk low"}}"#
        )
        transport.push(#"{"jsonrpc":"2.0","method":"notifications/message","params":{"level":"info","data":{"a":1}}}"#)
        #expect(await events.next() == .log(level: "warning", text: "disk low"))
        #expect(await events.next() == .log(level: "info", text: #"{"a":1}"#))
    }

    @Test func `lines that are not messages are reported and skipped, and the connection goes on`() async throws {
        let (connection, transport) = try await started()
        var events = connection.events.makeAsyncIterator()
        transport.push("Server listening on stdout, oops")
        transport.push("[1,2]")
        transport.push(#"{"jsonrpc":"2.0"}"#)
        transport.on("tools/list") { [$0.result(#"{"tools":[{"name":"ok"}]}"#)] }
        #expect(try await connection.listTools().map(\.name) == ["ok"])
        var skipped = 0
        while skipped < 3, case .malformed? = await events.next() { skipped += 1 }
        #expect(skipped == 3)
    }

    @Test func `progress for a call reaches that call's handler, and progress for nothing is ignored`() async throws {
        let (connection, transport) = try await started()
        let seen = Mutex<[MCPProgress]>([])
        transport.on("tools/call") { sent in
            let token =
                (try? AemiJSON.parse(Array((sent.params ?? "{}").utf8)).root["_meta"]["progressToken"].string) ?? ""
            return [
                #"{"jsonrpc":"2.0","method":"notifications/progress","params":{"progressToken":"unknown","progress":9}}"#,
                #"{"jsonrpc":"2.0","method":"notifications/progress","params":{"progressToken":"\#(token)","progress":1,"total":3,"message":"one"}}"#,
                #"{"jsonrpc":"2.0","method":"notifications/progress","params":{"progressToken":"\#(token)","progress":2.5}}"#,
                sent.result(#"{"content":[]}"#)
            ]
        }
        _ = try await connection.callTool("long", arguments: .empty) { progress in seen.withLock { $0.append(progress) }
        }
        #expect(
            seen.withLock { $0 } == [
                MCPProgress(progress: 1, total: 3, message: "one"), MCPProgress(progress: 2.5, total: nil, message: nil)
            ])
    }

    @Test func `a call that does not ask for progress carries no token`() async throws {
        let (connection, transport) = try await started()
        transport.on("tools/call") { [$0.result(#"{"content":[]}"#)] }
        _ = try await connection.callTool("quiet", arguments: .empty)
        #expect(transport.sent("tools/call").first?.params?.contains("progressToken") == false)
    }

    @Test func `ping from the client is answered by a server that answers`() async throws {
        let (connection, transport) = try await started()
        transport.on("ping") { [$0.result("{}")] }
        try await connection.ping()
        transport.on("ping") { [$0.failure(-32601, "no")] }
        await #expect(throws: MCPError.rpc(code: -32601, message: "no")) { try await connection.ping() }
    }
}
