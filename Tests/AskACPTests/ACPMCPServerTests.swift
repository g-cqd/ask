import AemiJSON
import Synchronization
import Testing

@testable import AskACP

/// ACP v1, Session Setup, "MCP servers" (ADR-0154).
@Suite("A client gives a session its MCP servers", .timeLimit(.minutes(1)))
struct ACPMCPServerTests {
    /// One line, as a message is.
    private static let listed = [
        #"[{"name":"files","command":"/bin/files","args":["--stdio",3,"x"],"#,
        #""env":[{"name":"KEY","value":"secret-1"},{"name":"odd"}]},"#,
        #"{"type":"http","name":"web","url":"https://example.test/mcp","#,
        #""headers":[{"name":"Authorization","value":"secret-2"}]},"#,
        #"{"type":"sse","name":"old","url":"https://example.test/sse","headers":[{"name":"X","value":"secret-3"}]},"#,
        #"{"name":"nothing","env":[{"name":"KEY","value":"secret-4"}]},"#,
        #"{"type":"http","headers":[{"name":"X","value":"secret-5"}]},{"type":"carrier-pigeon","name":"bird"},7]"#
    ]
    .joined()

    private static let usable = [
        ACPMCPServer(
            name: "files",
            command: "/bin/files",
            args: ["--stdio", "x"],
            env: ["KEY": "secret-1"],
            url: nil,
            headers: [:]
        ),
        ACPMCPServer(
            name: "web",
            command: nil,
            args: [],
            env: [:],
            url: "https://example.test/mcp",
            headers: ["Authorization": "secret-2"]
        )
    ]

    /// What the source and the loader were asked.
    private final class Asked: Sendable {
        private let all = Mutex<[ACPSession.Asked]>([])
        var each: [ACPSession.Asked] { all.withLock { $0 } }
        func note(_ asked: ACPSession.Asked) { all.withLock { $0.append(asked) } }
    }

    private func session(shows: String = "{}") async -> (client: ACPExchange, asked: Asked) {
        let asked = Asked()
        let conversation = DirectedConversation()
        let client = ACPExchange(
            sessions: { session in
                asked.note(session)
                return ACPSession(id: "s1", folder: session.cwd, conversation: conversation)
            },
            load: { id, session in
                asked.note(session)
                return ACPSession.Loaded(
                    session: ACPSession(id: id, folder: session.cwd, conversation: conversation),
                    history: []
                )
            }
        )
        _ = await client.initialize(capabilities: shows)
        return (client, asked)
    }

    @Test func `the servers that can be run are read, and each that cannot is said by its name and none of its values`()
        throws
    {
        let params = try AemiJSON.parse(Array(#"{"cwd":"/work","mcpServers":\#(Self.listed)}"#.utf8)).root
        let (servers, unusable) = ACPMCPServer.servers(of: params)
        #expect(servers == Self.usable)
        #expect(
            unusable == [
                "The MCP server old is spoken to over SSE, which ask does not: it is not connected to.",
                "The MCP server nothing names no command: it is not started.",
                "The MCP server at place 5 names no address: it is not connected to.",
                "The MCP server bird is of a kind ask does not know (carrier-pigeon): it is not connected to.",
                "The MCP server at place 7 names no command: it is not started."
            ]
        )
        #expect(!unusable.joined().contains("secret"))
    }

    @Test(arguments: [#"{"cwd":"/work"}"#, #"{"cwd":"/work","mcpServers":[]}"#, #"{"cwd":"/work","mcpServers":"none"}"#]
    )
    func `no servers named is no servers`(params: String) throws {
        let read = ACPMCPServer.servers(of: try AemiJSON.parse(Array(params.utf8)).root)
        #expect(read.servers.isEmpty && read.unusable.isEmpty)
    }

    @Test func `a new session and a loaded one are made with them, and one that cannot be run costs neither`() async {
        let (client, asked) = await session()
        let made = await client.request("session/new", #"{"cwd":"/work","mcpServers":\#(Self.listed)}"#)
        #expect(made["result"]["sessionId"].string == "s1")
        let (other, loaded) = await session()
        let answer = await other.request("session/load", #"{"sessionId":"s9","cwd":"/w","mcpServers":\#(Self.listed)}"#)
        #expect(answer["result"].exists)
        #expect(asked.each == [ACPSession.Asked(cwd: "/work", showsForms: false, servers: Self.usable)])
        #expect(loaded.each == [ACPSession.Asked(cwd: "/w", showsForms: false, servers: Self.usable)])
        // Neither client said it shows notices: nothing is said of the ones left out.
        #expect(client.updates.isEmpty && other.updates.isEmpty)
        _ = await client.end()
        _ = await other.end()
    }

    @Test func `a client that shows notices is told of each server left out, after the answer that made the session`()
        async
    {
        let (client, _) = await session(shows: #"{"session":{"notices":{}}}"#)
        _ = await client.request("session/new", #"{"cwd":"/work","mcpServers":\#(Self.listed)}"#)
        var titles: [String] = []
        for _ in 0 ..< 5 { titles.append(await client.nextUpdate()?["params"]["update"]["title"].string ?? "") }
        #expect(titles.first == "The MCP server old is spoken to over SSE, which ask does not: it is not connected to.")
        #expect(titles.count == 5 && !titles.contains(""))
        let kinds = client.log.prefix(3).map { $0["method"].string ?? "answer \($0["id"].int ?? 0)" }
        #expect(kinds == ["answer 1", "answer 2", "session/update"])
        _ = await client.end()
    }

    @Test func `ask says it speaks to a session's servers over HTTP, and not over SSE`() async {
        let client = ACPExchange { _ in ACPSession(id: "s1", folder: "/work", conversation: DirectedConversation()) }
        let opened = await client.initialize()
        #expect(JSONValue(opened["result"]["agentCapabilities"]) == ["mcpCapabilities": ["http": true]])
        _ = await client.end()
    }
}
