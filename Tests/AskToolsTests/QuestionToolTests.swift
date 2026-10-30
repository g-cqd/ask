import AemiJSON
import AskAI
import AskAgentCore
import Synchronization
import Testing

@testable import AskTools

/// The `question` tool (roadmap 0117): the model's questions reach the person whole, the answers come back one line per question, a
/// refusal says so, and a malformed question is refused with what is wrong, before anyone is asked.
@Suite("The model asks the person questions")
struct QuestionToolTests {
    private func input(_ json: String) -> JSONObject { try! JSONObject(validating: Array(json.utf8)) }

    private static let two = #"""
        {"questions": [
          {"question": "What should change?", "header": "Scope",
           "choices": [{"label": "Only the parser"}, {"label": "Everything", "description": "parser and printer"}]},
          {"question": "Which tests?", "header": "Tests", "choices": [{"label": "Unit"}, {"label": "Probes"}], "multiple": true,
           "note": "none"}
        ]}
        """#

    private func run(_ json: String, answering: [PersonAnswer]?) async -> (ToolOutput, [PersonQuestion]) {
        let asked = Mutex<[PersonQuestion]>([])
        let context = ToolContext(
            workingDirectory: "/tmp",
            askPerson: { questions in
                asked.withLock { $0 = questions }
                return answering
            })
        let output = await QuestionTool().run(input(json), in: context)
        return (output, asked.withLock { $0 })
    }

    @Test func `the questions reach the person whole, and each answer comes back as a line`() async {
        let (output, asked) = await run(
            Self.two,
            answering: [PersonAnswer(chosen: [0], note: "keep the API"), PersonAnswer(chosen: [0, 1], note: "")])
        #expect(
            asked.count == 2 && asked[0].header == "Scope" && asked[0].choices[1].description == "parser and printer")
        #expect(asked[1].multiple && asked[1].note == .none && asked[0].note == .optional)
        #expect(!output.isError)
        #expect(
            output.content == #"Scope: chose "Only the parser"; note: "keep the API""# + "\n"
                + #"Tests: chose "Unit", "Probes""#)
    }

    @Test func `an answer with neither choice nor note says so`() async {
        let (output, _) = await run(
            Self.two, answering: [PersonAnswer(chosen: [], note: ""), PersonAnswer(chosen: [1], note: "")])
        #expect(output.content.hasPrefix("Scope: no answer\n"))
    }

    @Test func `declining is said plainly, so the model goes on`() async {
        let (output, _) = await run(Self.two, answering: nil)
        #expect(!output.isError && output.content.contains("declined to answer"))
    }

    @Test(arguments: [
        (#"{"questions": []}"#, "1 to 4"),
        (#"{"questions": [{"question": "q", "header": "a header far too long"}]}"#, "12"),
        (#"{"questions": [{"question": "q", "header": "h", "note": "maybe"}]}"#, "note"),
        (#"{"questions": [{"header": "h"}]}"#, "question"),
        (#"{"questions": [{"question": "q", "header": "h", "choices": [{"description": "d"}]}]}"#, "label")
    ])
    func `a malformed question is refused before anyone is asked`(json: String, mentions: String) async {
        let (output, asked) = await run(json, answering: [])
        #expect(output.isError && output.content.contains(mentions) && asked.isEmpty, "\(output.content)")
    }

    @Test func `where no one can answer, the model is told to decide`() async {
        let output = await QuestionTool().run(input(Self.two), in: ToolContext(workingDirectory: "/tmp"))
        #expect(output.isError && output.content.contains("No one can answer"))
    }

    @Test func `the schema the model is given is JSON`() {
        #expect((try? AemiJSON.parse(Array(QuestionTool.schema.utf8))) != nil)
    }
}
