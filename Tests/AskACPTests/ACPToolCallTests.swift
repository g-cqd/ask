import AemiJSON
import AskTUI
import Testing

@testable import AskACP

/// Tool calls (ACP v1, Tool Calls): a call is told when it begins and when it ends, with what a client shows of it.
@Suite("A tool call is told when it begins and when it ends", .timeLimit(.minutes(1)))
struct ACPToolCallTests {
    /// The `update` of each `session/update` a turn of `said` sends, ended by the turn's end.
    private func updates(for said: ConversationUpdate...) async -> [JSONValue] {
        let conversation = DirectedConversation()
        let client = ACPExchange { _ in ACPSession(id: "s1", folder: "/work", conversation: conversation) }
        _ = await client.initialize()
        _ = await client.request("session/new", #"{"cwd":"/work"}"#)
        async let answer = client.request(
            "session/prompt",
            #"{"sessionId":"s1","prompt":[{"type":"text","text":"go"}]}"#
        )
        _ = await conversation.next()
        for update in said { conversation.say(update) }
        conversation.say(.runEnded)
        _ = await answer
        let sent = client.log.filter { $0["method"].string == "session/update" }
            .map { JSONValue($0["params"]["update"]) }
        _ = await client.end()
        return sent
    }

    @Test
    func `a read is told with its title, its kind and the file it names, then that it completed with what it returned`()
        async
    {
        let sent = await updates(
            for: .toolStarted(name: "read", summary: "note.txt", id: "t1", path: "note.txt"),
            .toolFinished(.succeeded, output: "the note\n", id: "t1")
        )
        let began: JSONValue = [
            "sessionUpdate": "tool_call", "toolCallId": "t1", "title": "read note.txt", "name": "read", "kind": "read",
            "status": "in_progress", "locations": [["path": "/work/note.txt"]]
        ]
        let ended: JSONValue = [
            "sessionUpdate": "tool_call_update", "toolCallId": "t1", "status": "completed",
            "content": [["type": "content", "content": ["type": "text", "text": "the note\n"]]]
        ]
        #expect(sent == [began, ended])
    }

    @Test func `a command is titled by its first line and carries the whole of it as its input`() async {
        let sent = await updates(
            for: .toolStarted(
                name: "shell",
                summary: "",
                id: "t2",
                fullInput: "make test\nmake lint",
                command: ToolCommand()
            ),
            .toolFinished(.failed("[exit 2]"), output: "boom\n[exit 2]", id: "t2")
        )
        let began: JSONValue = [
            "sessionUpdate": "tool_call", "toolCallId": "t2", "title": "make test …", "name": "shell",
            "kind": "execute",
            "status": "in_progress", "rawInput": ["command": "make test\nmake lint"]
        ]
        #expect(sent.first == began)
        #expect(sent.last?["status"] == "failed")
        #expect(sent.last?["content"] == [["type": "content", "content": ["type": "text", "text": "boom\n[exit 2]"]]])
    }

    @Test func `a write is an edit of the file it names, with what it writes as its content`() async {
        let sent = await updates(
            for: .toolStarted(name: "write", summary: "/tmp/a.txt", id: "t3", fullInput: "hello\n", path: "/tmp/a.txt")
        )
        let began: JSONValue = [
            "sessionUpdate": "tool_call", "toolCallId": "t3", "title": "write /tmp/a.txt", "name": "write",
            "kind": "edit",
            "status": "in_progress", "locations": [["path": "/tmp/a.txt"]],
            "content": [["type": "content", "content": ["type": "text", "text": "hello\n"]]]
        ]
        #expect(sent == [began])
    }

    @Test(arguments: [
        ("read", "read"), ("write", "edit"), ("edit", "edit"), ("fetch", "fetch"), ("shell", "other"),
        ("search_session", "search"), ("tasks", "other"), ("server tool", "other")
    ])
    func `each of ask's tools has ACP's kind, and one it does not know is other`(name: String, kind: String) {
        #expect(ACPToolCall.kind(of: name) == kind)
    }

    @Test func `a call with no summary is titled by its name, and one with nothing to return ends without content`()
        async
    {
        let sent = await updates(
            for: .toolStarted(name: "tasks", summary: "", id: "t4"),
            .toolFinished(.succeeded, id: "t4")
        )
        #expect(sent.first?["title"] == "tasks")
        #expect(sent.last == ["sessionUpdate": "tool_call_update", "toolCallId": "t4", "status": "completed"])
    }

    @Test func `a call the person stopped is failed, and one still running is in progress`() {
        #expect(ACPToolCall.finished(id: "t", .interrupted, output: "")["status"] == "failed")
        #expect(ACPToolCall.finished(id: "t", .running, output: "")["status"] == "in_progress")
    }

    @Test func `a block that is not a call of the model's has no id, and is not sent`() async {
        let sent = await updates(for: .toolStarted(name: "bash", summary: "ls"), .toolFinished(.succeeded, output: "a"))
        #expect(sent.isEmpty)
    }
}
