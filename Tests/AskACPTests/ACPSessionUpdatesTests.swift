import AemiJSON
import AskTUI
import Testing

@testable import AskACP

/// What a turn says besides the model's words and its calls (ACP v1, Prompt Turn): notices and compactions, to a client that said
/// it shows them; the session's title; how full its context is; how far a running call has got.
@Suite(
    "A turn's notices, compactions, title, usage and progress reach the client that shows them",
    .timeLimit(.minutes(1))
)
struct ACPSessionUpdatesTests {
    /// The `update` of each `session/update` a turn of `said` sends to a client with `capabilities`, ended by the turn's end.
    private func updates(capabilities: String = ACPExchange.showsEverything, for said: ConversationUpdate...) async
        -> [JSONValue]
    {
        let conversation = DirectedConversation()
        let client = ACPExchange { _ in ACPSession(id: "s1", folder: "/work", conversation: conversation) }
        _ = await client.initialize(capabilities: capabilities)
        _ = await client.request("session/new", #"{"cwd":"/work"}"#)
        async let answer = client.request(
            "session/prompt",
            #"{"sessionId":"s1","prompt":[{"type":"text","text":"go"}]}"#
        )
        _ = await conversation.next()
        for update in said { conversation.say(update) }
        conversation.say(.runEnded)
        _ = await answer
        let sent = client.updates.compactMap { $0["update"] }
        _ = await client.end()
        return sent
    }

    @Test func `a notice is told with its severity, its first line as the title and the rest as its description`() async
    {
        let sent = await updates(
            for: .notice("The configuration changed.", isError: false),
            .notice("The hook Lint failed.\nexit 2\nno such file", isError: true),
            .notice("", isError: false)
        )
        let expected: [JSONValue] = [
            ["sessionUpdate": "notice", "severity": "info", "title": "The configuration changed."],
            [
                "sessionUpdate": "notice", "severity": "error", "title": "The hook Lint failed.",
                "description": "exit 2\nno such file"
            ]
        ]
        #expect(sent == expected, "and a notice that says nothing is not one")
    }

    @Test(arguments: [
        "{}", #"{"session":{}}"#, #"{"session":{"notices":null,"compaction":null}}"#, #"{"session":null}"#
    ])
    func `a client that did not say it shows notices and compactions is sent neither`(capabilities: String) async {
        let sent = await updates(
            capabilities: capabilities,
            for: .notice("The configuration changed.", isError: false),
            .compacting(true),
            .compactionFinished(.succeeded, text: "Kept."),
            .assistantText("ok")
        )
        #expect(sent.compactMap { $0["sessionUpdate"] } == ["agent_message_chunk"])
    }

    @Test func `a compaction is one entity: begun, then completed with what it kept, under the same id`() async {
        let sent = await updates(
            for: .compacting(true),
            .compactionFinished(.succeeded, text: "They spoke of a note.", tokens: "182k → 3.1k tokens"),
            .compacting(false)
        )
        let expected: [JSONValue] = [
            ["sessionUpdate": "compaction_update", "compactionId": "compaction-1", "status": "in_progress"],
            [
                "sessionUpdate": "compaction_update", "compactionId": "compaction-1", "status": "completed",
                "summary": [["type": "text", "text": "They spoke of a note."]]
            ]
        ]
        #expect(sent == expected)
    }

    @Test func `one that failed says why, one that was stopped is cancelled, and each has an id of its own`() async {
        let sent = await updates(
            for: .compacting(true),
            .compactionFinished(.failed("failed"), text: "The model's server answered 529."),
            .compacting(true),
            .compactionFinished(.interrupted, text: ""),
            .compactionFinished(.succeeded, text: "")
        )
        let expected: [JSONValue] = [
            ["sessionUpdate": "compaction_update", "compactionId": "compaction-1", "status": "in_progress"],
            [
                "sessionUpdate": "compaction_update", "compactionId": "compaction-1", "status": "failed",
                "error": "The model's server answered 529."
            ], ["sessionUpdate": "compaction_update", "compactionId": "compaction-2", "status": "in_progress"],
            ["sessionUpdate": "compaction_update", "compactionId": "compaction-2", "status": "cancelled"],
            // One that ends with none begun is a compaction already done; with nothing kept to show, it has no summary.
            ["sessionUpdate": "compaction_update", "compactionId": "compaction-3", "status": "completed"]
        ]
        #expect(sent == expected)
    }

    @Test func `a compaction still running when its turn ends is said to be cancelled`() async {
        let sent = await updates(for: .compacting(true), .assistantText("stopped"))
        #expect(
            sent.last == ["sessionUpdate": "compaction_update", "compactionId": "compaction-1", "status": "cancelled"]
        )
    }

    @Test func `the session's name is its title, and none clears it`() async {
        let sent = await updates(
            capabilities: "{}",
            for: .conversationName("Fix the cache key"),
            .conversationName(nil)
        )
        let expected: [JSONValue] = [
            ["sessionUpdate": "session_info_update", "title": "Fix the cache key"],
            ["sessionUpdate": "session_info_update", "title": .null]
        ]
        #expect(sent == expected)
    }

    @Test func `a name that comes after its turn has ended is still told`() async {
        let conversation = DirectedConversation()
        let client = ACPExchange { _ in ACPSession(id: "s1", folder: "/work", conversation: conversation) }
        _ = await client.initialize()
        _ = await client.request("session/new", #"{"cwd":"/work"}"#)
        async let answer = client.request(
            "session/prompt",
            #"{"sessionId":"s1","prompt":[{"type":"text","text":"go"}]}"#
        )
        _ = await conversation.next()
        conversation.say(.runEnded)
        _ = await answer
        // The name is asked of a model while the turn runs, and may be chosen after it: said then, with what else comes late.
        conversation.say(.assistantText("late"), .gitStatus(["main"]), .batch([.conversationName("Named late")]))
        let expected: JSONValue = ["sessionUpdate": "session_info_update", "title": "Named late"]
        #expect(await client.nextUpdate().map { JSONValue($0["params"]["update"]) } == expected)
        // The others were said before it: had they been the client's, they would be here by the time a request is answered.
        _ = await client.request("session/new", #"{"cwd":"/work"}"#)
        #expect(client.updates.compactMap { $0["update"] } == [expected], "and nothing else said late is the client's")
        _ = await client.end()
    }

    @Test func `how full the context is, is told when it was measured, and not when it is unknown`() async {
        let sent = await updates(
            for: .context("26%/200k", used: 53_000, size: 200_000),
            .context("—%/200k", used: nil, size: 200_000),
            .context("—%/?")
        )
        #expect(sent == [["sessionUpdate": "usage_update", "used": 53_000, "size": 200_000]])
    }

    @Test func `how far a running call has got is on its title, which it has back when it ends`() async {
        let sent = await updates(
            for: .toolStarted(name: "read", summary: "big.log", id: "t1", path: "big.log"),
            .toolProgress(id: "t1", text: "40,000 lines"),
            .toolProgress(id: "t1", text: "80,000 lines"),
            .toolProgress(id: "other", text: "a call nobody began"),
            .toolFinished(.succeeded, output: "done", id: "t1"),
            .toolStarted(name: "read", summary: "small", id: "t2"),
            .toolFinished(.succeeded, id: "t2")
        )
        let progress: [JSONValue] = [
            ["sessionUpdate": "tool_call_update", "toolCallId": "t1", "title": "read big.log · 40,000 lines"],
            ["sessionUpdate": "tool_call_update", "toolCallId": "t1", "title": "read big.log · 80,000 lines"]
        ]
        #expect(Array(sent[1 ... 2]) == progress)
        #expect(sent[3]["title"] == "read big.log" && sent[3]["status"] == "completed")
        #expect(
            sent.last == ["sessionUpdate": "tool_call_update", "toolCallId": "t2", "status": "completed"],
            "no title to give back"
        )
        #expect(sent.count == 6)
    }
}
