import AemiJSON
import Synchronization
import Testing

@testable import AskACP

/// `session/new` (ACP v1, Session Setup) and what names a session afterwards (Errors, "Unknown sessions").
@Suite(
    "A session is made for an absolute directory, and only a session that was made is served",
    .timeLimit(.minutes(1))
)
struct ACPSessionTests {
    private struct Refused: Error, CustomStringConvertible {
        let description = "no model is configured"
    }

    @Test func `session new makes a session for the directory named, and answers its id`() async {
        let asked = Mutex<[String]>([])
        let client = ACPExchange { cwd in
            asked.withLock { $0.append(cwd) }
            return ACPSession(id: "2026-11-15T10-00-00", conversation: DirectedConversation())
        }
        _ = await client.initialize()
        let answer = await client.request("session/new", #"{"cwd":"/work/app","mcpServers":[]}"#)
        #expect(JSONValue(answer["result"]) == ["sessionId": "2026-11-15T10-00-00"])
        #expect(asked.withLock { $0 } == ["/work/app"])
        _ = await client.end()
    }

    @Test(arguments: [nil, "{}", #"{"cwd":"work/app"}"#, #"{"cwd":7}"#, #"{"cwd":""}"#])
    func `a directory that is missing or not absolute is refused, and no session is made`(params: String?) async {
        let asked = Mutex(0)
        let client = ACPExchange { _ in
            asked.withLock { $0 += 1 }
            return ACPSession(id: "s", conversation: DirectedConversation())
        }
        _ = await client.initialize()
        let answer = await client.request("session/new", params)
        #expect(answer["error"]["code"].int == -32602)
        #expect(answer["error"]["message"].string == "Invalid params: session/new needs cwd, an absolute path")
        #expect(asked.withLock { $0 } == 0)
        _ = await client.end()
    }

    @Test func `a session that cannot be made is an error that says why`() async {
        let client = ACPExchange { _ in throw Refused() }
        _ = await client.initialize()
        let answer = await client.request("session/new", #"{"cwd":"/work"}"#)
        #expect(answer["error"]["code"].int == -32603)
        #expect(answer["error"]["message"].string == "The session could not be made: no model is configured")
        _ = await client.end()
    }

    @Test func `a prompt for a session that was not made is not found, and names it`() async {
        let client = ACPExchange { _ in ACPSession(id: "made", conversation: DirectedConversation()) }
        _ = await client.initialize()
        _ = await client.request("session/new", #"{"cwd":"/work"}"#)
        let answer = await client.request(
            "session/prompt",
            #"{"sessionId":"other","prompt":[{"type":"text","text":"hi"}]}"#
        )
        #expect(answer["error"]["code"].int == -32002)
        #expect(JSONValue(answer["error"]["data"]) == ["sessionId": "other"])
        let unnamed = await client.request("session/prompt", #"{"prompt":[{"type":"text","text":"hi"}]}"#)
        #expect(unnamed["error"]["code"].int == -32602)
        _ = await client.end()
    }

    @Test func `a server that cannot make sessions has no session methods`() async {
        let client = ACPExchange()
        _ = await client.initialize()
        #expect(await client.request("session/new", #"{"cwd":"/work"}"#)["error"]["code"].int == -32601)
        #expect(
            await client.request("session/prompt", #"{"sessionId":"s","prompt":[]}"#)["error"]["code"].int == -32601
        )
        _ = await client.end()
    }
}
