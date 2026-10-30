internal import AemiJSON
public import AskAI
public import AskAgentCore

/// `question` (roadmap 0117): the model asks the person one question or a few, each with choices and room for a note; the answers come
/// back one line per question. Offered only where someone can answer; it never asks for approval itself.
public struct QuestionTool: Tool {
    public let definition = ToolDefinition(
        name: "question",
        description: """
            Ask the user up to 4 questions when only they can decide, each with up to 8 choices (one picked, or several with \
            "multiple": true) and room for a note of their own ("note": "optional", "required" or "none"). The header is a tab \
            label of at most 12 characters. Ask about real decisions, not to confirm what you were asked to do.
            """
    ) {
        ToolProperty.schema("questions", QuestionTool.schema)
    }

    static let schema = #"""
        {"type":"array","minItems":1,"maxItems":4,"items":{"type":"object","required":["question","header"],"properties":{\#
        "question":{"type":"string"},"header":{"type":"string","maxLength":12},\#
        "choices":{"type":"array","maxItems":8,"items":{"type":"object","required":["label"],"properties":{\#
        "label":{"type":"string"},"description":{"type":"string"}}}},\#
        "multiple":{"type":"boolean"},"note":{"type":"string","enum":["optional","required","none"]}}}}
        """#

    public init() {}

    public func run(_ input: JSONObject, in context: ToolContext) async -> ToolOutput {
        guard let ask = context.askPerson else {
            return .error("No one can answer questions in this run; decide yourself and say what you assumed.")
        }
        let questions: [PersonQuestion]
        do {
            questions = try Self.questions(in: input)
        } catch {
            return .error(error.reason)
        }
        guard let answers = await ask(questions), answers.count == questions.count else {
            return ToolOutput("The user declined to answer; continue with your own judgement and say what you assumed.")
        }
        return ToolOutput(zip(questions, answers).map(Self.line).joined(separator: "\n"))
    }

    /// `Scope: chose "Only the parser"; note: "keep the API"`.
    static func line(_ question: PersonQuestion, _ answer: PersonAnswer) -> String {
        let labels = answer.chosen.compactMap {
            question.choices.indices.contains($0) ? "\"\(question.choices[$0].label)\"" : nil
        }
        var parts = labels.isEmpty ? [] : ["chose " + labels.joined(separator: ", ")]
        if !answer.note.isEmpty { parts.append("note: \"\(answer.note)\"") }
        return "\(question.header): " + (parts.isEmpty ? "no answer" : parts.joined(separator: "; "))
    }

    /// What is wrong with the input, in words the model can act on.
    struct Malformed: Error {
        let reason: String
    }

    static func questions(in input: JSONObject) throws(Malformed) -> [PersonQuestion] {
        guard let document = try? AemiJSON.parse(input.bytes),
            case .object(let root) = JSONValue(document.root), case .array(let items)? = root["questions"],
            (1 ... 4).contains(items.count)
        else { throw Malformed(reason: "Give \"questions\": a list of 1 to 4 questions.") }
        return try items.enumerated().map { index, item throws(Malformed) in try question(item, number: index + 1) }
    }

    private static func question(_ item: JSONValue, number: Int) throws(Malformed) -> PersonQuestion {
        guard case .object(let fields) = item, case .string(let text)? = fields["question"], !text.isEmpty else {
            throw Malformed(reason: "Question \(number) needs \"question\", its words.")
        }
        guard case .string(let header)? = fields["header"], (1 ... 12).contains(header.count) else {
            throw Malformed(reason: "Question \(number) needs a \"header\" of 1 to 12 characters.")
        }
        var note = PersonQuestion.Note.optional
        if let given = fields["note"] {
            guard case .string(let word) = given, let parsed = PersonQuestion.Note(rawValue: word) else {
                throw Malformed(reason: "Question \(number): \"note\" is \"optional\", \"required\" or \"none\".")
            }
            note = parsed
        }
        let multiple = if case .bool(true)? = fields["multiple"] { true } else { false }
        return PersonQuestion(
            question: text, header: header, choices: try choices(fields["choices"], number: number), multiple: multiple,
            note: note)
    }

    private static func choices(_ value: JSONValue?, number: Int) throws(Malformed) -> [PersonQuestion.Choice] {
        guard let value else { return [] }
        guard case .array(let items) = value, items.count <= 8 else {
            throw Malformed(reason: "Question \(number): \"choices\" is a list of at most 8.")
        }
        return try items.map { item throws(Malformed) in
            guard case .object(let choice) = item, case .string(let label)? = choice["label"], !label.isEmpty else {
                throw Malformed(reason: "Question \(number): every choice needs a \"label\".")
            }
            let description: String? = if case .string(let text)? = choice["description"] { text } else { nil }
            return PersonQuestion.Choice(label: label, description: description)
        }
    }
}
