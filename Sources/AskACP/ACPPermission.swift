internal import AemiJSON
internal import AskTUI

/// An approval asked of the client (ACP v1, Tool Calls, "Requesting permission"): the answers the screen offers for the same
/// question, in the same words, so that an answer reaches as far through a client as it does on the screen. ask keeps what
/// "for the session" means; the option's name says it, as the specification asks.
enum ACPPermission {
    /// The `params` of `session/request_permission` for `question` about tool call `call`.
    static func request(session: String, call: String, question: String, detail: String?, kind: ApprovalKind)
        -> JSONValue
    {
        var toolCall: OrderedDictionary<String, JSONValue> = [
            "toolCallId": .string(call), "title": .string(question), "status": "pending"
        ]
        if let detail, !detail.isEmpty { toolCall["content"] = [ACPToolCall.text(detail)] }
        let options = ApprovalOption.options(for: kind)
            .map { option -> JSONValue in
                [
                    "optionId": .string(id(of: option.choice)), "name": .string(option.label),
                    "kind": .string(hint(for: option.choice))
                ]
            }
        return ["sessionId": .string(session), "toolCall": .object(toolCall), "options": .array(options)]
    }

    /// What the client's answer chooses among the answers of `kind`. Anything but one of them is a refusal: no answer, the turn
    /// cancelled, an option that was not offered.
    static func choice(from answer: JSON?, kind: ApprovalKind) -> ApprovalChoice {
        guard let outcome = answer?["outcome"], outcome["outcome"].string == "selected",
            let chosen = outcome["optionId"].string
        else { return .deny }
        return ApprovalOption.options(for: kind).map(\.choice).first { id(of: $0) == chosen } ?? .deny
    }

    private static func id(of choice: ApprovalChoice) -> String {
        switch choice {
            case .once: "once"
            case .session: "session"
            case .program: "program"
            case .deny: "deny"
        }
    }

    /// ACP's hint for a client's icon; what the answer does is ask's, said by its name.
    private static func hint(for choice: ApprovalChoice) -> String {
        switch choice {
            case .once: "allow_once"
            case .session, .program: "allow_always"
            case .deny: "reject_once"
        }
    }
}
