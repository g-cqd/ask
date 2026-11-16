import AemiJSON
import AskTUI
import Testing

@testable import AskACP

/// A prompt turn (ACP v1, Prompt Turn): the prompt starts a turn of the session's conversation, what the conversation says goes
/// to the client as `session/update` in the order it was said, and the request is answered after the last of them.
@Suite("A prompt starts a turn, its updates follow in order, and its answer comes last", .timeLimit(.minutes(1)))
struct ACPPromptTurnTests {
    /// A client with one session, `s1`, served by the conversation returned.
    private func session(_ id: String = "s1") async -> (client: ACPExchange, conversation: DirectedConversation) {
        let conversation = DirectedConversation()
        let client = ACPExchange { _ in ACPSession(id: id, folder: "/work", conversation: conversation) }
        _ = await client.initialize()
        _ = await client.request("session/new", #"{"cwd":"/work"}"#)
        return (client, conversation)
    }

    private func prompt(_ text: String, in session: String = "s1") -> String {
        #"{"sessionId":"\#(session)","prompt":[{"type":"text","text":"\#(text)"}]}"#
    }

    private func chunk(_ kind: String, _ text: String, in session: String = "s1") -> JSONValue {
        [
            "sessionId": .string(session),
            "update": ["sessionUpdate": .string(kind), "content": ["type": "text", "text": .string(text)]]
        ]
    }

    @Test func `the model's words and its reasoning are chunks, in order, and the answer follows them`() async {
        let (client, conversation) = await session()
        async let answer = client.request("session/prompt", prompt("hello"))
        #expect(await conversation.next() == .started("hello"))
        conversation.say(
            .thinkingText("The person"),
            .thinkingText(" greets."),
            .assistantText("Hi"),
            .assistantText("!")
        )
        conversation.say(.runEnded)
        let answered = await answer
        #expect(JSONValue(answered["result"]) == ["stopReason": "end_turn"])
        let expected = [
            chunk("agent_thought_chunk", "The person"), chunk("agent_thought_chunk", " greets."),
            chunk("agent_message_chunk", "Hi"), chunk("agent_message_chunk", "!")
        ]
        #expect(client.updates == expected)
        #expect(client.log.last?["id"].int == answered["id"].int, "the answer is written after every update")
        _ = await client.end()
    }

    @Test func `a list of updates is its members, and what is not for a client is not sent`() async {
        let (client, conversation) = await session()
        async let answer = client.request("session/prompt", prompt("go"))
        _ = await conversation.next()
        conversation.say(
            .batch([.assistantText("a"), .status("12k tokens"), .batch([.assistantText("b")])]),
            .gitStatus(["main"]),
            .label("model"),
            .notice("The configuration changed.", isError: false)
        )
        conversation.say(.batch([.assistantText("c"), .runEnded]))
        _ = await answer
        #expect(
            client.updates == [
                chunk("agent_message_chunk", "a"), chunk("agent_message_chunk", "b"), chunk("agent_message_chunk", "c")
            ]
        )
        _ = await client.end()
    }

    @Test func `what is said after the turn's end is not sent as part of it`() async {
        let (client, conversation) = await session()
        async let answer = client.request("session/prompt", prompt("go"))
        _ = await conversation.next()
        conversation.say(.assistantText("done"), .runEnded, .assistantText("late"))
        _ = await answer
        #expect(client.updates == [chunk("agent_message_chunk", "done")])
        _ = await client.end()
    }

    @Test func `a turn that failed is an error that says why, after what it had said`() async {
        let (client, conversation) = await session()
        async let answer = client.request("session/prompt", prompt("go"))
        _ = await conversation.next()
        conversation.say(.assistantText("I will"), .notice("The model's server answered 529.", isError: true))
        // What is said after the reason, and is not an error, does not replace it.
        conversation.say(.notice("Your message is back in the input.", isError: false), .returnQueuedPrompts, .runEnded)
        let answered = await answer
        #expect(answered["error"]["code"].int == -32603)
        #expect(answered["error"]["message"].string == "The model's server answered 529.")
        #expect(!answered["result"].exists)
        #expect(client.updates == [chunk("agent_message_chunk", "I will")])
        _ = await client.end()
    }

    @Test func `an error said during a turn that went on is not its failure`() async {
        let (client, conversation) = await session()
        async let answer = client.request("session/prompt", prompt("go"))
        _ = await conversation.next()
        conversation.say(.notice("A hook failed.", isError: true), .assistantText("Still here."), .runEnded)
        #expect(JSONValue(await answer["result"]) == ["stopReason": "end_turn"])
        _ = await client.end()
    }

    @Test func `the next prompt starts the next turn of the same conversation`() async {
        let (client, conversation) = await session()
        for (text, said) in [("one", "1"), ("two", "2")] {
            async let answer = client.request("session/prompt", prompt(text))
            #expect(await conversation.next() == .started(text))
            conversation.say(.assistantText(said), .runEnded)
            #expect(await answer["result"]["stopReason"].string == "end_turn")
        }
        #expect(client.updates == [chunk("agent_message_chunk", "1"), chunk("agent_message_chunk", "2")])
        _ = await client.end()
    }

    @Test func `each session's updates name it`() async {
        let first = DirectedConversation()
        let second = DirectedConversation()
        let client = ACPExchange { asked in
            asked.cwd == "/one"
                ? ACPSession(id: "a", folder: "/work", conversation: first)
                : ACPSession(id: "b", folder: "/work", conversation: second)
        }
        _ = await client.initialize()
        #expect(await client.request("session/new", #"{"cwd":"/one"}"#)["result"]["sessionId"].string == "a")
        #expect(await client.request("session/new", #"{"cwd":"/two"}"#)["result"]["sessionId"].string == "b")
        async let one = client.request("session/prompt", prompt("for a", in: "a"))
        #expect(await first.next() == .started("for a"))
        async let two = client.request("session/prompt", prompt("for b", in: "b"))
        #expect(await second.next() == .started("for b"))
        second.say(.assistantText("B"), .runEnded)
        _ = await two
        first.say(.assistantText("A"), .runEnded)
        _ = await one
        #expect(
            client.updates == [chunk("agent_message_chunk", "B", in: "b"), chunk("agent_message_chunk", "A", in: "a")]
        )
        _ = await client.end()
    }

    /// Until the client can be asked these (elicitation: the order of work), nobody can answer: a turn that waited for an answer
    /// would never end.
    @Test func `what nobody can be asked yet is declined at once, so the turn goes on`() async {
        let (client, conversation) = await session()
        async let answer = client.request("session/prompt", prompt("go"))
        _ = await conversation.next()
        conversation.say(.askQuestions(id: 5, questions: []))
        #expect(await conversation.next() == .answeredQuestions(5, nil))
        conversation.say(.askInput(id: 6, prompt: "Your key", secret: true))
        #expect(await conversation.next() == .answeredInput(6, nil))
        conversation.say(.assistantText("I could not."), .runEnded)
        #expect(await answer["result"]["stopReason"].string == "end_turn")
        #expect(client.updates == [chunk("agent_message_chunk", "I could not.")])
        _ = await client.end()
    }
}
