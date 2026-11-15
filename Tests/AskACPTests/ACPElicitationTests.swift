import AemiJSON
import AskTUI
import Testing

@testable import AskACP

/// The model's questions for the person (ACP v1, Elicitation): one form, asked of a client that said it shows forms, whose
/// answer is the conversation's. A client that cannot show one is not asked, and the questions are declined.
@Suite(
    "The model's questions are a form the client shows, and its answer is the conversation's",
    .timeLimit(.minutes(1))
)
struct ACPElicitationTests {
    private let questions = [
        ScreenQuestion(
            question: "Which protocol should serve speak?",
            header: "Protocol",
            choices: [.init(label: "ACP", detail: "One protocol for every editor."), .init(label: "Its own")],
            note: .none
        ),
        ScreenQuestion(
            question: "Which editors matter?",
            header: "Editors",
            choices: [.init(label: "Zed"), .init(label: "VS Code"), .init(label: "Neovim")],
            multiple: true,
            note: .required
        ), ScreenQuestion(question: "What should the command be called?", header: "Name", choices: [], note: .optional)
    ]

    private let prompt = #"{"sessionId":"s1","prompt":[{"type":"text","text":"go"}]}"#

    /// A client with `capabilities` in a turn that has just asked `questions` as question 7, and where the prompt's answer will
    /// be: a mailbox, since a wait on a task's value would hold the test for ever with a server that never answers.
    private func asking(_ capabilities: String = ACPExchange.showsForms) async -> (
        ACPExchange, DirectedConversation, Mailbox<JSON>
    ) {
        let conversation = DirectedConversation()
        let client = ACPExchange { _ in ACPSession(id: "s1", folder: "/work", conversation: conversation) }
        _ = await client.initialize(capabilities: capabilities)
        _ = await client.request("session/new", #"{"cwd":"/work"}"#)
        let answer = Mailbox<JSON>()
        Task { [prompt] in answer.post(await client.request("session/prompt", prompt)) }
        _ = await conversation.next()
        conversation.say(
            .toolStarted(name: "question", summary: "3 questions", id: "t1"),
            .askQuestions(id: 7, questions: questions)
        )
        return (client, conversation, answer)
    }

    @Test func `they are one form: a property a question, its choices by their words, its note beside it`() async {
        let (client, conversation, answer) = await asking()
        let asked = await client.nextRequest()
        #expect(asked?["method"].string == "elicitation/create")
        let expected: JSONValue = [
            "sessionId": "s1", "toolCallId": "t1", "mode": "form", "message": "3 questions",
            "requestedSchema": [
                "type": "object",
                "properties": [
                    "q1": [
                        "type": "string", "title": "Protocol", "description": "Which protocol should serve speak?",
                        "oneOf": [
                            ["const": "ACP", "title": "ACP", "description": "One protocol for every editor."],
                            ["const": "Its own", "title": "Its own"]
                        ]
                    ],
                    "q2": [
                        "type": "array", "title": "Editors", "description": "Which editors matter?",
                        "items": [
                            "anyOf": [
                                ["const": "Zed", "title": "Zed"], ["const": "VS Code", "title": "VS Code"],
                                ["const": "Neovim", "title": "Neovim"]
                            ]
                        ]
                    ], "q2_note": ["type": "string", "title": "Editors (note)"],
                    "q3": ["type": "string", "title": "Name", "description": "What should the command be called?"]
                ],
                "required": ["q1", "q2_note"]
            ]
        ]
        #expect(asked.map { JSONValue($0["params"]) } == expected)
        client.respond(
            to: asked,
            #"{"action":"accept","content":{"q1":"Its own","q2":["Neovim","Zed"],"q2_note":"In that order.","q3":"serve"}}"#
        )
        let answers = [
            QuestionAnswer(chosen: [1], note: ""), QuestionAnswer(chosen: [0, 2], note: "In that order."),
            QuestionAnswer(chosen: [], note: "serve")
        ]
        #expect(await conversation.next() == .answeredQuestions(7, answers))
        conversation.say(.runEnded)
        _ = await answer.next()
        _ = await client.end()
    }

    @Test func `one question is asked in its own words`() async {
        let conversation = DirectedConversation()
        let client = ACPExchange { _ in ACPSession(id: "s1", folder: "/work", conversation: conversation) }
        _ = await client.initialize(capabilities: ACPExchange.showsForms)
        _ = await client.request("session/new", #"{"cwd":"/work"}"#)
        let answer = Mailbox<JSON>()
        Task { [prompt] in answer.post(await client.request("session/prompt", prompt)) }
        _ = await conversation.next()
        // No call of the model's behind it: the form names the session alone.
        conversation.say(.askQuestions(id: 2, questions: [questions[2]]))
        let asked = await client.nextRequest()
        #expect(asked?["params"]["message"].string == "What should the command be called?")
        #expect(asked?["params"]["toolCallId"].exists == false)
        #expect(asked?["params"]["requestedSchema"]["required"].exists == false, "nothing in it is required")
        client.respond(to: asked, #"{"action":"accept","content":{}}"#)
        #expect(await conversation.next() == .answeredQuestions(2, [QuestionAnswer(chosen: [], note: "")]))
        conversation.say(.runEnded)
        _ = await answer.next()
        _ = await client.end()
    }

    @Test(
        arguments: [
            #"{"action":"decline"}"#, #"{"action":"cancel"}"#, #"{"action":"_later"}"#, "{}", nil,
            // Accepted, and not what was asked: a required answer missing, a choice that was not offered, the wrong shape.
            #"{"action":"accept"}"#, #"{"action":"accept","content":{"q1":"ACP","q2":["Zed"]}}"#,
            #"{"action":"accept","content":{"q1":"Emacs","q2_note":"n"}}"#,
            #"{"action":"accept","content":{"q1":["ACP"],"q2_note":"n"}}"#
        ] as [String?]
    )
    func `anything but an answer to what was asked declines them`(result: String?) async {
        let (client, conversation, answer) = await asking()
        client.respond(to: await client.nextRequest(), result)
        #expect(await conversation.next() == .answeredQuestions(7, nil))
        conversation.say(.runEnded)
        _ = await answer.next()
        _ = await client.end()
    }

    @Test func `what was not asked is left out of an answer, and a choice is taken once, in the order it was offered`()
        async
    {
        let (client, conversation, answer) = await asking()
        client.respond(
            to: await client.nextRequest(),
            #"{"action":"accept","content":{"q1":"ACP","q1_note":"not asked","q2":["Neovim","Emacs","Zed","Zed"],"q2_note":"x","q9":1}}"#
        )
        let answers = [
            QuestionAnswer(chosen: [0], note: ""), QuestionAnswer(chosen: [0, 2], note: "x"),
            QuestionAnswer(chosen: [], note: "")
        ]
        #expect(await conversation.next() == .answeredQuestions(7, answers))
        conversation.say(.runEnded)
        _ = await answer.next()
        _ = await client.end()
    }

    @Test(arguments: [
        "{}", #"{"elicitation":{}}"#, #"{"elicitation":{"form":null,"url":{}}}"#, #"{"elicitation":null}"#
    ])
    func `a client that did not say it shows forms is not asked, and they are declined at once`(capabilities: String)
        async
    {
        let (client, conversation, answer) = await asking(capabilities)
        #expect(await conversation.next() == .answeredQuestions(7, nil))
        conversation.say(.runEnded)
        _ = await answer.next()
        _ = await client.end()
        #expect(
            !client.log.contains { $0["method"].string == "elicitation/create" },
            "no request was made of the client"
        )
    }

    @Test func `a form nobody answers does not hold a cancelled turn`() async {
        let (client, conversation, answer) = await asking()
        #expect(await client.nextRequest()?["method"].string == "elicitation/create")
        client.notify("session/cancel", #"{"sessionId":"s1"}"#)
        let said = [await conversation.next(), await conversation.next()]
        #expect(said.contains(.stopped) && said.contains(.answeredQuestions(7, nil)), "\(said)")
        conversation.say(.returnQueuedPrompts, .runEnded)
        #expect(await answer.next()?["result"]["stopReason"].string == "cancelled")
        _ = await client.end()
    }
}
