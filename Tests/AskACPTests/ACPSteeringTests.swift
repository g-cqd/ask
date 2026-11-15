import AemiJSON
import AskTUI
import Testing

@testable import AskACP

/// A prompt sent while a turn runs (ADR-0154): it steers the turn, as Enter does on the screen, and is answered when the turn ends.
@Suite("A prompt sent during a turn steers it, and none is lost", .timeLimit(.minutes(1)))
struct ACPSteeringTests {
    private func session() async -> (client: ACPExchange, conversation: DirectedConversation) {
        let conversation = DirectedConversation()
        let client = ACPExchange { _ in ACPSession(id: "s1", conversation: conversation) }
        _ = await client.initialize()
        _ = await client.request("session/new", #"{"cwd":"/work"}"#)
        return (client, conversation)
    }

    private func prompt(_ text: String) -> String {
        #"{"sessionId":"s1","prompt":[{"type":"text","text":"\#(text)"}]}"#
    }

    @Test func `it is offered to the running turn as steering, and both are answered when the turn ends`() async {
        let (client, conversation) = await session()
        async let first = client.request("session/prompt", prompt("build it"))
        #expect(await conversation.next() == .started("build it"))
        async let second = client.request("session/prompt", prompt("in Swift"))
        guard case .enqueued("in Swift", let id, followUp: false) = await conversation.next() else {
            Issue.record("the second prompt was not offered to the turn as steering")
            return
        }
        conversation.say(.promptAccepted(id: id, text: "in Swift"), .assistantText("Done."), .runEnded)
        #expect(JSONValue(await first["result"]) == ["stopReason": "end_turn"])
        #expect(JSONValue(await second["result"]) == ["stopReason": "end_turn"])
        _ = await client.end()
    }

    @Test func `one the turn ended without taking starts the next turn, and is answered at that turn's end`() async {
        let (client, conversation) = await session()
        async let first = client.request("session/prompt", prompt("build it"))
        _ = await conversation.next()
        async let second = client.request("session/prompt", prompt("then test it"))
        _ = await conversation.next()
        // The turn ends without a `promptAccepted` for it.
        conversation.say(.assistantText("Built."), .runEnded)
        #expect(await first["result"]["stopReason"].string == "end_turn")
        #expect(await conversation.next() == .started("then test it"))
        conversation.say(.assistantText("Tested."), .runEnded)
        #expect(await second["result"]["stopReason"].string == "end_turn")
        _ = await client.end()
    }

    @Test func `a turn that failed answers the prompts sent during it with its failure, and starts nothing`() async {
        let (client, conversation) = await session()
        async let first = client.request("session/prompt", prompt("build it"))
        _ = await conversation.next()
        async let second = client.request("session/prompt", prompt("then test it"))
        _ = await conversation.next()
        conversation.say(.notice("No network.", isError: true), .returnQueuedPrompts, .runEnded)
        #expect(await first["error"]["message"].string == "No network.")
        #expect(await second["error"]["message"].string == "No network.")
        // The session is free again: the next prompt starts a turn, not the one that failed with the other.
        async let third = client.request("session/prompt", prompt("again"))
        #expect(await conversation.next() == .started("again"))
        conversation.say(.runEnded)
        #expect(await third["result"]["stopReason"].string == "end_turn")
        _ = await client.end()
    }

    @Test func `one the conversation refuses is told why, and the turn goes on`() async {
        let (client, conversation) = await session()
        async let first = client.request("session/prompt", prompt("build it"))
        _ = await conversation.next()
        async let second = client.request("session/prompt", prompt("/skill:missing"))
        guard case .enqueued(_, let id, _) = await conversation.next() else {
            Issue.record("the second prompt was not offered to the turn")
            return
        }
        conversation.say(.notice("There is no skill named missing.", isError: true), .promptRefused(id: id))
        let refused = await second
        #expect(refused["error"]["code"].int == -32602)
        #expect(refused["error"]["message"].string == "Invalid params: There is no skill named missing.")
        conversation.say(.assistantText("Built."), .runEnded)
        #expect(await first["result"]["stopReason"].string == "end_turn")
        _ = await client.end()
    }
}
