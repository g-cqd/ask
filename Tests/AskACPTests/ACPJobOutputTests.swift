import AemiJSON
import AskTUI
import Testing

@testable import AskACP

/// A command that goes on after its call has ended (a `bash` call that yielded) belongs to no turn: what it prints is told on
/// the call that started it, whenever it prints it.
@Suite("What a command prints after its call has ended is told on that call, until it ends", .timeLimit(.minutes(1)))
struct ACPJobOutputTests {
    private let prompt = #"{"sessionId":"s1","prompt":[{"type":"text","text":"build it"}]}"#
    private let start = ContinuousClock.now

    private func job(_ output: String, _ status: Transcript.ToolStatus = .running, ending: String = "ended")
        -> JobUpdate
    {
        JobUpdate(id: "job-1", label: "#7a2f", output: output, status: status, startedAt: start, ending: ending)
    }

    /// A session whose first turn has ended, having started `job-1` with the call `t1`: the client, and the conversation.
    private func yielded() async -> (client: ACPExchange, conversation: DirectedConversation) {
        let conversation = DirectedConversation()
        let client = ACPExchange { _ in ACPSession(id: "s1", folder: "/work", conversation: conversation) }
        _ = await client.initialize()
        _ = await client.request("session/new", #"{"cwd":"/work"}"#)
        async let answer = client.request("session/prompt", prompt)
        #expect(await conversation.next() == .started("build it"))
        conversation.say(
            .toolStarted(name: "bash", summary: "", id: "t1", fullInput: "make watch", command: ToolCommand()),
            .toolFinished(.succeeded, output: "started\n", id: "t1", backgroundJob: "job-1")
        )
        #expect(await conversation.next() == .watched("job-1"))
        conversation.say(.runEnded)
        #expect(await answer["result"]["stopReason"].string == "end_turn")
        return (client, conversation)
    }

    private func told(_ text: String) -> JSONValue {
        [
            "sessionUpdate": "tool_call_update", "toolCallId": "t1",
            "content": [["type": "content", "content": ["type": "text", "text": .string(text)]]]
        ]
    }

    @Test
    func `it is told after the call's end and after the turn's, with no status, and how it ended is its last line`()
        async
    {
        let (client, conversation) = await yielded()
        let before = client.updates.map { $0["update"]?["status"] }
        #expect(before == ["in_progress", "completed"], "the call ended when the tool returned")
        _ = await client.nextUpdate()
        _ = await client.nextUpdate()
        conversation.say(job: job("started\nbuilt 1\n"))
        #expect(await client.nextUpdate().map { JSONValue($0["params"]["update"]) } == told("started\nbuilt 1\n"))
        conversation.say(job: job("started\nbuilt 1\nbuilt 2", .succeeded))
        let last = await client.nextUpdate()
        #expect(last.map { JSONValue($0["params"]["update"]) } == told("started\nbuilt 1\nbuilt 2\n[#7a2f] ended"))
        #expect(last?["params"]["sessionId"].string == "s1")
        #expect(await conversation.next() == .unwatched("job-1"), "a job that ended is no longer watched")
        _ = await client.end()
    }

    @Test func `what it has already been told is not told again, and a job that fails says why`() {
        var output = ACPJobOutput(call: "t1")
        #expect(output.update(for: job("")) == told(""), "that it runs and has printed nothing is news once")
        #expect(output.update(for: job("")) == nil)
        #expect(output.update(for: job("one\n")) == told("one\n"))
        #expect(output.update(for: job("one\n")) == nil)
        #expect(output.update(for: job("one\ntwo\n")) == told("one\ntwo\n"))
        let failed = job("one\ntwo\n", .failed("[exit 2]"), ending: "failed")
        #expect(
            output.update(for: failed) == told("one\ntwo\n[#7a2f] failed: [exit 2]"),
            "its end is said, with nothing new"
        )
    }

    @Test(arguments: [
        [".running", ""], [".succeeded", "[#7a2f] ended"], ["stopped", "[#7a2f] stopped"],
        ["signal 9", "[#7a2f] signalled: signal 9"], ["", "[#7a2f] failed"]
    ])
    func `how a job ended is said as the screen says it, with the reason when it adds one`(pair: [String]) {
        let status: Transcript.ToolStatus =
            switch pair[0] {
                case ".running": .running
                case ".succeeded": .succeeded
                default: .failed(pair[0])
            }
        let ending = pair[0].hasPrefix("signal") ? "signalled" : pair[0] == "stopped" ? "stopped" : "failed"
        let said = ACPJobOutput.ending(of: job("", status, ending: status == .succeeded ? "ended" : ending))
        #expect(said ?? "" == pair[1])
        var output = ACPJobOutput(call: "t1")
        #expect(output.update(for: job("", status, ending: "ended"))?["content"]?.items?.count == 1)
    }

    @Test
    func `a job is no longer watched when the client has gone, and one a later call reports is told on that call`()
        async
    {
        let (client, conversation) = await yielded()
        async let answer = client.request("session/prompt", prompt)
        #expect(await conversation.next() == .started("build it"))
        conversation.say(
            .toolStarted(name: "job", summary: "wait", id: "t2"),
            .toolFinished(.succeeded, output: "", id: "t2", backgroundJob: "job-1")
        )
        let watched = [await conversation.next(), await conversation.next()]
        #expect(watched.contains(.watched("job-1")) && watched.contains(.unwatched("job-1")), "\(watched)")
        conversation.say(.runEnded)
        _ = await answer
        conversation.say(job: job("later\n"))
        var update = await client.nextUpdate()
        while let other = update, JSONValue(other["params"]["update"]["content"]) != told("later\n")["content"] {
            update = await client.nextUpdate()
        }
        #expect(update?["params"]["update"]["toolCallId"].string == "t2")
        client.hangUp()
        #expect(await conversation.next() == .unwatched("job-1"), "nobody is left to tell")
        _ = await client.end()
    }

    @Test func `a job a saved call left running is not watched when the session is loaded: it ended with its process`()
        async
    {
        let conversation = DirectedConversation()
        let history: [ConversationUpdate] = [
            .toolStarted(name: "bash", summary: "", id: "t1", fullInput: "make watch", command: ToolCommand()),
            .toolFinished(.succeeded, output: "started\n", id: "t1", backgroundJob: "job-1")
        ]
        let client = ACPExchange(
            sessions: { _ in ACPSession(id: "s0", folder: "/work", conversation: DirectedConversation()) },
            load: { id, _ in
                ACPSession.Loaded(
                    session: ACPSession(id: id, folder: "/work", conversation: conversation),
                    history: history
                )
            }
        )
        _ = await client.initialize()
        let loaded = await client.request("session/load", #"{"sessionId":"s1","cwd":"/work","mcpServers":[]}"#)
        #expect(JSONValue(loaded["result"]) == [:])
        #expect(client.updates.count == 2, "the call is replayed")
        Task { _ = await client.request("session/prompt", prompt) }
        #expect(await conversation.next() == .started("build it"), "nothing was asked of the conversation before")
        conversation.say(.runEnded)
        _ = await client.end()
    }
}
