import AemiJSON
import AskTUI
import Testing

@testable import AskACP

/// ACP v1, Slash Commands (ADR-0154): the client is told the commands it can run, and a prompt that is one of them runs it.
@Suite("A client is told the commands a session serves, and runs one by typing it", .timeLimit(.minutes(1)))
struct ACPCommandsTests {
    private static let commands = [
        SlashCommand(name: "tasks", summary: "Show the session's task list."),
        SlashCommand(name: "compact", summary: "Summarise the conversation now."),
        SlashCommand(name: "model", summary: "Choose a model.", takesChoices: true)
    ]
    private static let skills = [SlashCommand(name: "skill:debugging", summary: "skill · Find a defect's cause.")]

    private static let told: JSONValue = [
        "sessionUpdate": "available_commands_update",
        "availableCommands": [
            ["name": "tasks", "description": "Show the session's task list."],
            ["name": "compact", "description": "Summarise the conversation now."],
            [
                "name": "skill:debugging", "description": "skill · Find a defect's cause.",
                "input": ["hint": "what to do with it"]
            ]
        ]
    ]

    private func session() async -> (client: ACPExchange, conversation: DirectedConversation) {
        let conversation = DirectedConversation(commands: Self.commands, skills: Self.skills)
        let client = ACPExchange(
            sessions: { _ in ACPSession(id: "s1", folder: "/work", conversation: conversation) },
            load: { id, _ in
                ACPSession.Loaded(
                    session: ACPSession(id: id, folder: "/work", conversation: conversation),
                    history: [.userPrompt("before")]
                )
            }
        )
        _ = await client.initialize()
        return (client, conversation)
    }

    private func prompt(_ text: String) -> String {
        #"{"sessionId":"s1","prompt":[{"type":"text","text":"\#(text)"}]}"#
    }

    /// The client learns the session's id from the answer: commands sent before it would be those of a session it has not heard of.
    @Test func `a new session's commands are told after its answer: those served, and the skills`() async {
        let (client, _) = await session()
        let made = await client.request("session/new", #"{"cwd":"/work"}"#)
        #expect(made["result"]["sessionId"].string == "s1")
        let update = await client.nextUpdate()
        #expect(JSONValue(update?["params"] ?? made) == ["sessionId": "s1", "update": Self.told])
        let kinds = client.log.map { $0["method"].string ?? "answer \($0["id"].int ?? 0)" }
        #expect(kinds == ["answer 1", "answer 2", "session/update"])
        _ = await client.end()
    }

    @Test func `a loaded session's commands are told after what it holds and before the answer`() async {
        let (client, _) = await session()
        _ = await client.request("session/load", #"{"sessionId":"s1","cwd":"/work"}"#)
        #expect(client.updates.count == 2)
        #expect(client.updates.last == ["sessionId": "s1", "update": Self.told])
        _ = await client.end()
    }

    @Test func `a prompt that is a served command runs it, and what the command says is the answer`() async {
        let (client, conversation) = await session()
        _ = await client.request("session/new", #"{"cwd":"/work"}"#)
        _ = await client.nextUpdate()
        async let asked = client.request("session/prompt", prompt("/tasks all"))
        #expect(await conversation.next() == .commanded("tasks", "all"))
        conversation.say(.notice("t1 open: write the page", isError: false), .runEnded)
        #expect(JSONValue(await asked["result"]) == ["stopReason": "end_turn"])
        // Shown by every client: this one did not say it shows notices.
        let said: JSONValue = [
            "sessionUpdate": "agent_message_chunk",
            "content": ["type": "text", "text": "t1 open: write the page\n"]
        ]
        #expect(client.updates.last == ["sessionId": "s1", "update": said])
        _ = await client.end()
    }

    /// A path, a command the conversation has and serve does not, a skill (which the conversation expands), a name it has not,
    /// and a command kept from being one by a second slash.
    @Test(arguments: [
        ["/Users/me/a.swift explain", "/Users/me/a.swift explain"], ["/model opus", "/model opus"],
        ["/skill:debugging fix it", "/skill:debugging fix it"], ["/search x", "/search x"], ["//tasks", "/tasks"],
        ["//Users", "//Users"]
    ])
    func `any other prompt that starts with a slash is the model's, with one slash fewer where two escaped a command`(
        pair: [String]
    ) async {
        let (client, conversation) = await session()
        _ = await client.request("session/new", #"{"cwd":"/work"}"#)
        async let asked = client.request("session/prompt", prompt(pair[0]))
        #expect(await conversation.next() == .started(pair[1]))
        conversation.say(.runEnded)
        #expect(await asked["result"]["stopReason"].string == "end_turn")
        _ = await client.end()
    }

    /// The command steers nothing: it is a turn of its own. Whether it arrived before the turn's end or after, it runs after it.
    @Test func `a command sent during the model's turn runs when that turn has ended, and is answered at its own end`()
        async
    {
        let (client, conversation) = await session()
        _ = await client.request("session/new", #"{"cwd":"/work"}"#)
        async let first = client.request("session/prompt", prompt("build it"))
        #expect(await conversation.next() == .started("build it"))
        async let second = client.request("session/prompt", prompt("/compact"))
        async let third = client.request("session/prompt", prompt("//compact now"))
        guard case .enqueued("/compact now", let id, followUp: false) = await conversation.next() else {
            Issue.record("the escaped prompt did not steer the turn, or the command did")
            return
        }
        conversation.say(.promptAccepted(id: id, text: "/compact now"), .runEnded)
        #expect(await first["result"]["stopReason"].string == "end_turn")
        #expect(await third["result"]["stopReason"].string == "end_turn")
        #expect(await conversation.next() == .commanded("compact", ""))
        conversation.say(.notice("Compacted.", isError: false), .runEnded)
        #expect(await second["result"]["stopReason"].string == "end_turn")
        _ = await client.end()
    }

    /// Where a prompt goes as it arrives, without the tasks that bring it: a turn's answer does not say when the next came.
    @Test func `a command steers no turn and is steered by none, and what was cancelled goes nowhere`() {
        var model = ACPTurns.State()
        #expect(model.place(1, isCommand: false) == .starts)
        #expect(model.place(2, isCommand: false) == .steers)
        #expect(model.place(3, isCommand: true) == .waits)
        var command = ACPTurns.State()
        #expect(command.place(1, isCommand: true) == .starts)
        #expect(command.place(2, isCommand: false) == .waits)
        #expect(command.place(3, isCommand: true) == .waits)
        command.cancelledThrough = 4
        #expect(command.place(4, isCommand: false) == .cancelled)
        #expect(command.place(5, isCommand: false) == .waits)
    }

    @Test func `a prompt sent while a command runs steers nothing, and starts the next turn`() async {
        let (client, conversation) = await session()
        _ = await client.request("session/new", #"{"cwd":"/work"}"#)
        async let first = client.request("session/prompt", prompt("/compact"))
        #expect(await conversation.next() == .commanded("compact", ""))
        async let second = client.request("session/prompt", prompt("go on"))
        conversation.say(.runEnded)
        #expect(await first["result"]["stopReason"].string == "end_turn")
        #expect(await conversation.next() == .started("go on"))
        conversation.say(.runEnded)
        #expect(await second["result"]["stopReason"].string == "end_turn")
        #expect(conversation.everything == [.commanded("compact", ""), .started("go on")])
        _ = await client.end()
    }
}
