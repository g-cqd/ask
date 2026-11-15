import AemiJSON
import AskTUI
import Testing

@testable import AskACP

/// Cancellation (ACP v1, Prompt Turn, "Cancellation"): `session/cancel` stops the turn as Esc does, and the prompt is answered
/// `cancelled`, never with an error, after what the turn had still to say.
@Suite("A cancel stops the turn, and its prompt answers cancelled", .timeLimit(.minutes(1)))
struct ACPCancelTests {
    private func session() async -> (client: ACPExchange, conversation: DirectedConversation) {
        let conversation = DirectedConversation()
        let client = ACPExchange { _ in ACPSession(id: "s1", folder: "/work", conversation: conversation) }
        _ = await client.initialize()
        _ = await client.request("session/new", #"{"cwd":"/work"}"#)
        return (client, conversation)
    }

    private func prompt(_ text: String) -> String {
        #"{"sessionId":"s1","prompt":[{"type":"text","text":"\#(text)"}]}"#
    }
    private let cancelled: JSONValue = ["stopReason": "cancelled"]

    @Test func `the conversation's run is cancelled, and the answer comes after what it still said`() async {
        let (client, conversation) = await session()
        async let answer = client.request("session/prompt", prompt("build it"))
        #expect(await conversation.next() == .started("build it"))
        conversation.say(.assistantText("Working"))
        client.notify("session/cancel", #"{"sessionId":"s1"}"#)
        #expect(await conversation.next() == .stopped)
        // What a conversation says when its run is cancelled: no error, its queued messages given back, the end.
        conversation.say(.assistantText(" on it."), .returnQueuedPrompts, .runEnded)
        let answered = await answer
        #expect(JSONValue(answered["result"]) == cancelled)
        #expect(!answered["error"].exists, "a cancellation is not an error")
        #expect(client.updates.count == 2 && client.log.last?["id"].int == answered["id"].int)
        _ = await client.end()
    }

    @Test func `a cancel written right behind its prompt is not lost`() async {
        let (client, conversation) = await session()
        // Either the turn had not begun, and never does, or it had, and is stopped: the conversation is driven whichever it is.
        let driving = Task {
            guard await conversation.next() == .started("go") else { return }
            _ = await conversation.next()
            conversation.say(.returnQueuedPrompts, .runEnded)
        }
        let line = #"{"jsonrpc":"2.0","id":70,"method":"session/prompt","params":\#(prompt("go"))}"# + "\n"
        client.send(raw: [line + #"{"jsonrpc":"2.0","method":"session/cancel","params":{"sessionId":"s1"}}"# + "\n"])
        #expect(JSONValue(await client.answer(to: 70)["result"]) == cancelled)
        driving.cancel()
        _ = await client.end()
    }

    /// The same, where the order is certain: the prompt admitted, the cancellation read, and only then the prompt's work.
    @Test func `a prompt cancelled before its work began starts nothing`() async {
        let conversation = DirectedConversation()
        let turns = ACPTurns(session: ACPSession(id: "s1", folder: "/work", conversation: conversation))
        let client = ACPClient(notify: { _ in }, requestPermission: { _ in nil }, elicit: { _ in nil })
        let admitted = turns.admit()
        turns.cancel()
        // Awaited through a mailbox: a prompt that is never answered then fails the test at its time limit, and does not hold it.
        let answers = Mailbox<ACPTurns.Outcome>()
        Task { answers.post(await turns.prompt("go", admitted: admitted, client: client)) }
        #expect(await answers.next() == .success(cancelled))
        #expect(conversation.everything.isEmpty, "the conversation was not started")
        // And the cancellation is spent: the next prompt runs.
        let next = turns.admit()
        Task { answers.post(await turns.prompt("again", admitted: next, client: client)) }
        #expect(await conversation.next() == .started("again"))
        conversation.say(.runEnded)
        #expect(await answers.next() == .success(["stopReason": "end_turn"]))
    }

    @Test func `the prompts sent before the cancel are cancelled with the turn, and nothing starts after`() async {
        let (client, conversation) = await session()
        async let first = client.request("session/prompt", prompt("build it"))
        _ = await conversation.next()
        async let second = client.request("session/prompt", prompt("in Swift"))
        guard case .enqueued = await conversation.next() else {
            Issue.record("the second prompt was not offered to the turn")
            return
        }
        client.notify("session/cancel", #"{"sessionId":"s1"}"#)
        #expect(await conversation.next() == .stopped)
        conversation.say(.returnQueuedPrompts, .runEnded)
        #expect(JSONValue(await first["result"]) == cancelled)
        #expect(JSONValue(await second["result"]) == cancelled)
        // The session is free: the next prompt starts a turn of its own.
        async let third = client.request("session/prompt", prompt("again"))
        #expect(await conversation.next() == .started("again"))
        conversation.say(.runEnded)
        #expect(await third["result"]["stopReason"].string == "end_turn")
        _ = await client.end()
    }

    @Test func `a prompt sent after the cancel is the next turn, not cancelled with the one that is stopping`() async {
        let (client, conversation) = await session()
        async let first = client.request("session/prompt", prompt("build it"))
        _ = await conversation.next()
        client.notify("session/cancel", #"{"sessionId":"s1"}"#)
        #expect(await conversation.next() == .stopped)
        async let second = client.request("session/prompt", prompt("something else"))
        guard case .enqueued = await conversation.next() else {
            Issue.record("the second prompt was not offered to the turn that is stopping")
            return
        }
        conversation.say(.returnQueuedPrompts, .runEnded)
        #expect(JSONValue(await first["result"]) == cancelled)
        #expect(await conversation.next() == .started("something else"))
        conversation.say(.assistantText("Done."), .runEnded)
        #expect(await second["result"]["stopReason"].string == "end_turn")
        _ = await client.end()
    }

    @Test func `an approval still asked when the cancel comes is not waited for`() async {
        let (client, conversation) = await session()
        async let answer = client.request("session/prompt", prompt("build it"))
        _ = await conversation.next()
        conversation.say(
            .toolStarted(name: "shell", summary: "", id: "t1", fullInput: "make", command: ToolCommand()),
            .askApproval(id: 5, question: "Run `make`?", kind: .grant)
        )
        // The client is asked, and does not answer.
        #expect(await client.nextRequest()?["method"].string == "session/request_permission")
        client.notify("session/cancel", #"{"sessionId":"s1"}"#)
        let said = [await conversation.next(), await conversation.next()]
        #expect(said.contains(.stopped) && said.contains(.answeredApproval(5, .deny)), "\(said)")
        conversation.say(.returnQueuedPrompts, .runEnded)
        #expect(JSONValue(await answer["result"]) == cancelled)
        _ = await client.end()
    }

    @Test func `a cancel with no turn to stop, or for no session, does nothing, and the next prompt runs`() async {
        let (client, conversation) = await session()
        client.notify("session/cancel", #"{"sessionId":"s1"}"#)
        client.notify("session/cancel", #"{"sessionId":"nope"}"#)
        client.notify("session/cancel", "{}")
        async let answer = client.request("session/prompt", prompt("go"))
        #expect(await conversation.next() == .started("go"))
        conversation.say(.runEnded)
        #expect(await answer["result"]["stopReason"].string == "end_turn")
        #expect(await client.end().isEmpty, "a notification is never answered")
    }

    @Test func `a turn that failed on its own is still an error`() async {
        let (client, conversation) = await session()
        async let answer = client.request("session/prompt", prompt("go"))
        _ = await conversation.next()
        conversation.say(.notice("No network.", isError: true), .returnQueuedPrompts, .runEnded)
        #expect(await answer["error"]["message"].string == "No network.")
        _ = await client.end()
    }
}
