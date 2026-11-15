internal import AemiJSON
internal import AskTUI

/// The model's questions for the person as a form (ACP v1, Elicitation, form mode), and the form's answer as the person's.
///
/// A question is a property `qN`: one of its choices (`oneOf`), several (`type: array`), or words when it has no choices. A
/// choice is named by its own words, so an answer reads as what it says. A question with choices that also takes words of the
/// person's own has them in `qN_note`. A form never asks for a secret, and no question of the model's is one.
enum ACPElicitation {
    /// The `params` of `elicitation/create` for `questions`, in `session`, about tool call `call` when there is one.
    static func request(session: String, call: String?, questions: [ScreenQuestion]) -> JSONValue {
        var properties: OrderedDictionary<String, JSONValue> = [:]
        var required: [JSONValue] = []
        for (index, question) in questions.enumerated() {
            let key = "q\(index + 1)"
            var property: OrderedDictionary<String, JSONValue> = [
                "type": question.choices.isEmpty || !question.multiple ? "string" : "array",
                "title": .string(question.header), "description": .string(question.question)
            ]
            if !question.choices.isEmpty {
                let options = JSONValue.array(question.choices.map(option))
                if question.multiple { property["items"] = ["anyOf": options] } else { property["oneOf"] = options }
            }
            properties[key] = .object(property)
            if !question.choices.isEmpty, question.note != .none {
                properties[key + "_note"] = ["type": "string", "title": .string("\(question.header) (note)")]
            }
            if let needed = requirement(of: question, as: key) { required.append(.string(needed)) }
        }
        var schema: OrderedDictionary<String, JSONValue> = ["type": "object", "properties": .object(properties)]
        if !required.isEmpty { schema["required"] = .array(required) }
        var params: OrderedDictionary<String, JSONValue> = ["sessionId": .string(session)]
        if let call { params["toolCallId"] = .string(call) }
        params["mode"] = "form"
        params["message"] = .string(questions.count == 1 ? questions[0].question : "\(questions.count) questions")
        params["requestedSchema"] = .object(schema)
        return .object(params)
    }

    /// The person's answers in what the client answered, one for each of `questions`; nil when the form was declined, was
    /// dismissed, got no answer, or was accepted without what it requires: the questions are then declined.
    static func answers(from answer: JSON?, to questions: [ScreenQuestion]) -> [QuestionAnswer]? {
        guard let answer, answer["action"].string == "accept" else { return nil }
        let content = answer["content"]
        var answers: [QuestionAnswer] = []
        for (index, question) in questions.enumerated() {
            let key = "q\(index + 1)"
            let labels = question.choices.map(\.label)
            // What was not offered is left out; a choice is taken once, in the order it was offered.
            let said =
                question.multiple
                ? (content[key].array ?? []).compactMap(\.string) : [content[key].string].compactMap { $0 }
            let chosen = Set(said.compactMap { labels.firstIndex(of: $0) }).sorted()
            let words = content[labels.isEmpty ? key : key + "_note"].string ?? ""
            let note = question.note == .none && !labels.isEmpty ? "" : words
            // What the form requires and an answer lacks: a required property is the question's words, or else its choice.
            if let needed = requirement(of: question, as: key) {
                let missing = needed == key && !labels.isEmpty ? chosen.isEmpty : note.isEmpty
                if missing { return nil }
            }
            answers.append(QuestionAnswer(chosen: chosen, note: note))
        }
        return answers
    }

    /// The property of `question`, asked as `key`, that an answer must hold: its words when words are required, its choice when
    /// it takes nothing else; nil when it may be left unanswered.
    private static func requirement(of question: ScreenQuestion, as key: String) -> String? {
        switch (question.note, question.choices.isEmpty) {
            case (.required, false): key + "_note"
            case (.required, true), (.none, false): key
            default: nil
        }
    }

    /// One choice as the form offers it: named and titled by its words, described by what it means.
    private static func option(_ choice: ScreenQuestion.Choice) -> JSONValue {
        var option: OrderedDictionary<String, JSONValue> = [
            "const": .string(choice.label), "title": .string(choice.label)
        ]
        if let detail = choice.detail, !detail.isEmpty { option["description"] = .string(detail) }
        return .object(option)
    }
}
