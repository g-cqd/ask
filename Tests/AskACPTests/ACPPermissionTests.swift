import AemiJSON
import AskTUI
import Testing

@testable import AskACP

/// Approvals (ACP v1, Tool Calls, "Requesting permission"): what the screen would ask the person is asked of the client, with the
/// same answers in the same words, and the client's answer is the conversation's.
@Suite("An approval is asked of the client, and its answer is the conversation's", .timeLimit(.minutes(1)))
struct ACPPermissionTests {
    private func session() async -> (client: ACPExchange, conversation: DirectedConversation) {
        let conversation = DirectedConversation()
        let client = ACPExchange { _ in ACPSession(id: "s1", folder: "/work", conversation: conversation) }
        _ = await client.initialize()
        _ = await client.request("session/new", #"{"cwd":"/work"}"#)
        return (client, conversation)
    }

    private let prompt = #"{"sessionId":"s1","prompt":[{"type":"text","text":"go"}]}"#
    private let make = ConversationUpdate.toolStarted(
        name: "bash",
        summary: "",
        id: "t1",
        fullInput: "make",
        command: ToolCommand()
    )

    @Test func `it names the call that waits, asks the screen's question, and offers the screen's answers`() async {
        let (client, conversation) = await session()
        async let answer = client.request("session/prompt", prompt)
        _ = await conversation.next()
        let kind = ApprovalKind.command(phrases: ["make"], programs: ["make"])
        conversation.say(
            make,
            .askApproval(id: 9, question: "Run `make`?", kind: kind, detail: "It is not in the allowed list.")
        )
        let asked = await client.nextRequest()
        #expect(asked?["method"].string == "session/request_permission")
        let expected: JSONValue = [
            "sessionId": "s1",
            "toolCall": [
                "toolCallId": "t1", "title": "Run `make`?", "status": "pending",
                "content": [["type": "content", "content": ["type": "text", "text": "It is not in the allowed list."]]]
            ],
            "options": [
                ["optionId": "once", "name": "Allow this time", "kind": "allow_once"],
                ["optionId": "session", "name": "Allow `make` for the session", "kind": "allow_always"],
                ["optionId": "deny", "name": "Deny", "kind": "reject_once"]
            ]
        ]
        #expect(asked.map { JSONValue($0["params"]) } == expected)
        client.respond(to: asked, #"{"outcome":{"outcome":"selected","optionId":"session"}}"#)
        #expect(await conversation.next() == .answeredApproval(9, .session))
        conversation.say(.toolFinished(.succeeded, output: "built", id: "t1"), .runEnded)
        _ = await answer
        // The call is told to run again under its own title, then to have completed.
        let after = client.updates.compactMap { $0["update"] }.dropFirst()
        #expect(
            after.first == [
                "sessionUpdate": "tool_call_update", "toolCallId": "t1", "title": "make", "status": "in_progress"
            ]
        )
        #expect(after.last?["status"] == "completed")
        _ = await client.end()
    }

    @Test(
        arguments: [
            (#"{"outcome":{"outcome":"selected","optionId":"once"}}"#, ApprovalChoice.once),
            (#"{"outcome":{"outcome":"selected","optionId":"deny"}}"#, .deny),
            (#"{"outcome":{"outcome":"cancelled"}}"#, .deny),
            // What was not offered, what is not an outcome and no answer at all are refusals, never an approval.
            (#"{"outcome":{"outcome":"selected","optionId":"program"}}"#, .deny),
            (#"{"outcome":{"outcome":"selected","optionId":"always"}}"#, .deny), (#"{"outcome":"selected"}"#, .deny),
            ("{}", .deny),
            (nil, .deny)
        ] as [(String?, ApprovalChoice)]
    )
    func `the client's answer chooses among what was offered, and anything else refuses`(
        result: String?,
        choice: ApprovalChoice
    ) async {
        let (client, conversation) = await session()
        async let answer = client.request("session/prompt", prompt)
        _ = await conversation.next()
        conversation.say(make, .askApproval(id: 3, question: "Run `make`?", kind: .grant))
        client.respond(to: await client.nextRequest(), result)
        #expect(await conversation.next() == .answeredApproval(3, choice))
        conversation.say(.runEnded)
        _ = await answer
        let resumed = client.updates.last?["update"]
        #expect(resumed?["title"] == "make")
        #expect(resumed?["status"] == (choice == .deny ? nil : "in_progress"), "a refused call is not said to run")
        _ = await client.end()
    }

    /// The conversation's question does not say which call it is about; a call asks before it runs, so it is the last begun.
    @Test func `with several calls begun, the question is about the last, and one that ended is not it`() async {
        let (client, conversation) = await session()
        async let answer = client.request("session/prompt", prompt)
        _ = await conversation.next()
        conversation.say(
            .toolStarted(name: "read", summary: "a", id: "r1"),
            .toolStarted(name: "read", summary: "b", id: "r2")
        )
        conversation.say(
            make,
            .toolFinished(.succeeded, id: "t1"),
            .askApproval(id: 1, question: "Read b?", kind: .grant)
        )
        let asked = await client.nextRequest()
        #expect(asked?["params"]["toolCall"]["toolCallId"].string == "r2")
        client.respond(to: asked, #"{"outcome":{"outcome":"selected","optionId":"once"}}"#)
        _ = await conversation.next()
        conversation.say(.runEnded)
        _ = await answer
        #expect(client.updates.last?["update"]?["title"] == "read b")
        _ = await client.end()
    }

    @Test func `a question with no call of the model's behind it is a call of its own, which ends with the answer`()
        async
    {
        let (client, conversation) = await session()
        async let answer = client.request("session/prompt", prompt)
        _ = await conversation.next()
        conversation.say(.askApproval(id: 4, question: "Open the link with `open`?", kind: .opener(remembers: true)))
        let asked = await client.nextRequest()
        #expect(asked?["params"]["toolCall"]["toolCallId"].string == "approval-4")
        #expect(
            asked?["params"]["options"].array?.map { $0["name"].string } == [
                "Allow this time", "Always allow this command", "Deny"
            ]
        )
        client.respond(to: asked, #"{"outcome":{"outcome":"selected","optionId":"deny"}}"#)
        #expect(await conversation.next() == .answeredApproval(4, .deny))
        conversation.say(.runEnded)
        _ = await answer
        #expect(
            client.updates.last?["update"] == [
                "sessionUpdate": "tool_call_update", "toolCallId": "approval-4", "status": "failed"
            ]
        )
        _ = await client.end()
    }

    @Test(arguments: [
        (ApprovalKind.grant, ["once", "session", "deny"]), (.destructive, ["once", "session", "deny"]),
        (.confirm, ["once", "deny"]),
        (.command(phrases: [], programs: []), ["once", "deny"]),
        (.command(phrases: ["git status"], programs: ["git"]), ["once", "session", "program", "deny"]),
        (.opener(remembers: false), ["once", "deny"])
    ])
    func `each kind of question offers its answers, each with an id of its own`(kind: ApprovalKind, ids: [String]) {
        let request = ACPPermission.request(session: "s", call: "c", question: "q", detail: nil, kind: kind)
        #expect(request["options"]?.items?.compactMap { $0["optionId"] } == ids.map { JSONValue.string($0) })
        #expect(request["toolCall"]?["content"] == nil, "no detail, no content")
    }
}
