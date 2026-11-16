import AemiJSON
import AskTUI
import Synchronization
import Testing

@testable import AskACP

/// `session/load` (ACP v1, Session Setup, "Loading sessions"): a saved session is opened, what it holds is replayed as updates,
/// and the request is answered after the last of them; the session then takes prompts like one just made.
@Suite("A saved session is replayed to the client, then continued", .timeLimit(.minutes(1)))
struct ACPLoadTests {
    private struct Locked: Error, CustomStringConvertible {
        let description = "session s9 is open in another ask"
    }

    private let history: [ConversationUpdate] = [
        .userPrompt("What does note.txt say?"), .thinkingText("I should read it."),
        .toolStarted(name: "read", summary: "note.txt", id: "t1", path: "note.txt"),
        .toolFinished(.succeeded, output: "the note\n", id: "t1"),
        .batch([.assistantText("It says: the note.")]),
        // What a record's replay also says, and no client is sent: a notice of the time, the screen's status.
        .notice("The model's server was slow.", isError: true), .status("12k tokens"), .context("4%"),
        .userPrompt("Thanks."),
        .compactionFinished(.succeeded, text: "They spoke of a note.", tokens: "9k → 1k tokens"),
        .assistantText("Any time.")
    ]

    /// What the loader was asked, in order.
    private final class Asked: Sendable {
        private let values = Mutex<[String]>([])
        func note(_ value: String) { values.withLock { $0.append(value) } }
        var all: [String] { values.withLock { $0 } }
    }

    /// A client of a server that can load `s9` of `/work`, and the conversation that then serves it.
    private func client() -> (client: ACPExchange, conversation: DirectedConversation, asked: Asked) {
        let conversation = DirectedConversation()
        let asked = Asked()
        let history = history
        let client = ACPExchange(
            sessions: { _ in ACPSession(id: "new", folder: "/work", conversation: DirectedConversation()) },
            load: { id, session in
                asked.note("\(id) in \(session.cwd)\(session.showsForms ? ", with forms" : "")")
                guard id == "s9" else { return nil }
                guard session.cwd == "/work" else { throw Locked() }
                return ACPSession.Loaded(
                    session: ACPSession(id: id, folder: session.cwd, conversation: conversation) {
                        history + [.assistantText("And since.")]
                    },
                    history: history
                )
            }
        )
        return (client, conversation, asked)
    }

    private func chunk(_ kind: String, _ text: String) -> JSONValue {
        ["sessionUpdate": .string(kind), "content": ["type": "text", "text": .string(text)]]
    }

    @Test func `a server that can load says so, and one that cannot does not`() async {
        let (able, _, _) = client()
        #expect(await able.initialize()["result"]["agentCapabilities"]["loadSession"].bool == true)
        _ = await able.end()
        let unable = ACPExchange { _ in ACPSession(id: "s", folder: "/work", conversation: DirectedConversation()) }
        #expect(!(await unable.initialize()["result"]["agentCapabilities"]["loadSession"].exists))
        #expect(
            await unable.request("session/load", #"{"sessionId":"s9","cwd":"/work"}"#)["error"]["code"].int == -32601
        )
        _ = await unable.end()
    }

    @Test func `the loader is told whether the client shows forms`() async {
        let (client, _, asked) = client()
        _ = await client.initialize(capabilities: ACPExchange.showsForms)
        _ = await client.request("session/load", #"{"sessionId":"s9","cwd":"/work"}"#)
        #expect(asked.all == ["s9 in /work, with forms"])
        _ = await client.end()
    }

    @Test func `what the session holds is replayed in order, each update naming it, and the answer follows the last`()
        async
    {
        let (client, _, asked) = client()
        // A client that shows notices: the one the session holds is still not replayed, being no part of its history.
        _ = await client.initialize(capabilities: ACPExchange.showsEverything)
        let answer = await client.request("session/load", #"{"sessionId":"s9","cwd":"/work","mcpServers":[]}"#)
        #expect(JSONValue(answer["result"]) == [:])
        #expect(asked.all == ["s9 in /work"])
        let expected: [JSONValue] = [
            chunk("user_message_chunk", "What does note.txt say?"), chunk("agent_thought_chunk", "I should read it."),
            [
                "sessionUpdate": "tool_call", "toolCallId": "t1", "title": "read note.txt", "name": "read",
                "kind": "read",
                "status": "in_progress", "locations": [["path": "/work/note.txt"]]
            ],
            [
                "sessionUpdate": "tool_call_update", "toolCallId": "t1", "status": "completed",
                "content": [["type": "content", "content": ["type": "text", "text": "the note\n"]]]
            ],
            chunk("agent_message_chunk", "It says: the note."), chunk("user_message_chunk", "Thanks."),
            // A compaction the session holds is one that is done: one update, with what it kept.
            [
                "sessionUpdate": "compaction_update", "compactionId": "compaction-1", "status": "completed",
                "summary": [["type": "text", "text": "They spoke of a note."]]
            ],
            chunk("agent_message_chunk", "Any time.")
        ]
        #expect(client.updates.compactMap { $0["update"] } == expected)
        #expect(client.updates.allSatisfy { $0["sessionId"] == "s9" })
        #expect(client.log.last?["id"].int == answer["id"].int, "the answer is written after every update")
        _ = await client.end()
    }

    @Test func `the loaded session then takes prompts`() async {
        let (client, conversation, _) = client()
        _ = await client.initialize()
        _ = await client.request("session/load", #"{"sessionId":"s9","cwd":"/work"}"#)
        async let answer = client.request(
            "session/prompt",
            #"{"sessionId":"s9","prompt":[{"type":"text","text":"And now?"}]}"#
        )
        #expect(await conversation.next() == .started("And now?"))
        conversation.say(.assistantText("Now this."), .runEnded)
        #expect(await answer["result"]["stopReason"].string == "end_turn")
        #expect(client.updates.last?["update"] == chunk("agent_message_chunk", "Now this."))
        _ = await client.end()
    }

    @Test func `a session that is not there is not found, and one that cannot be opened says why`() async {
        let (client, _, _) = client()
        _ = await client.initialize()
        let missing = await client.request("session/load", #"{"sessionId":"other","cwd":"/work"}"#)
        #expect(missing["error"]["code"].int == -32002)
        #expect(JSONValue(missing["error"]["data"]) == ["sessionId": "other"])
        let locked = await client.request("session/load", #"{"sessionId":"s9","cwd":"/elsewhere"}"#)
        #expect(locked["error"]["code"].int == -32603)
        #expect(
            locked["error"]["message"].string == "The session could not be loaded: session s9 is open in another ask"
        )
        #expect(client.updates.isEmpty, "nothing is replayed of a session that was not loaded")
        _ = await client.end()
    }

    @Test(arguments: [
        nil, "{}", #"{"sessionId":"s9"}"#, #"{"sessionId":"s9","cwd":"work"}"#, #"{"cwd":"/work"}"#,
        #"{"sessionId":7,"cwd":"/work"}"#
    ])
    func `a load without an id and an absolute directory is refused, and nothing is opened`(params: String?) async {
        let (client, _, asked) = client()
        _ = await client.initialize()
        let answer = await client.request("session/load", params)
        #expect(answer["error"]["code"].int == -32602)
        #expect(
            answer["error"]["message"].string
                == "Invalid params: session/load needs sessionId, and cwd, an absolute path"
        )
        #expect(asked.all.isEmpty)
        _ = await client.end()
    }

    @Test
    func `a session the connection already serves is told again from what it holds now, and stays the one it was`()
        async
    {
        let (client, conversation, asked) = client()
        _ = await client.initialize()
        _ = await client.request("session/load", #"{"sessionId":"s9","cwd":"/work"}"#)
        let first = client.updates.count
        let again = await client.request("session/load", #"{"sessionId":"s9","cwd":"/elsewhere"}"#)
        #expect(JSONValue(again["result"]) == [:])
        #expect(asked.all.count == 1, "its file has one writer: nothing is opened again")
        let told = client.updates.dropFirst(first).map { $0["update"] }
        #expect(told.count == first + 1 && told.last == chunk("agent_message_chunk", "And since."), "\(told)")
        async let answer = client.request(
            "session/prompt",
            #"{"sessionId":"s9","prompt":[{"type":"text","text":"go on"}]}"#
        )
        #expect(await conversation.next() == .started("go on"), "the conversation it had")
        conversation.say(.runEnded)
        #expect(await answer["result"]["stopReason"].string == "end_turn")
        _ = await client.end()
    }

    @Test func `one with a turn running is not told again until the turn has ended`() async {
        let (client, conversation, _) = client()
        _ = await client.initialize()
        _ = await client.request("session/load", #"{"sessionId":"s9","cwd":"/work"}"#)
        let first = client.updates.count
        async let answer = client.request(
            "session/prompt",
            #"{"sessionId":"s9","prompt":[{"type":"text","text":"go on"}]}"#
        )
        #expect(await conversation.next() == .started("go on"))
        let during = await client.request("session/load", #"{"sessionId":"s9","cwd":"/work"}"#)
        #expect(during["error"]["code"].int == -32602)
        #expect(
            during["error"]["message"].string
                == "Invalid params: session s9 has a turn running: load it again once the turn has ended"
        )
        #expect(client.updates.count == first, "nothing of the history is mixed with the turn's")
        conversation.say(.runEnded)
        _ = await answer
        #expect(JSONValue(await client.request("session/load", #"{"sessionId":"s9","cwd":"/work"}"#)["result"]) == [:])
        _ = await client.end()
    }
}
