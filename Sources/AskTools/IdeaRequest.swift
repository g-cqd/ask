internal import AskAgentCore

/// What an `ideas` call asks: an id as `i3` or `3`.
public struct IdeaRequest: Decodable, Sendable {
    let action: String
    let id: IdeaID?
    let all: Bool?

    struct IdeaID: Decodable, Sendable {
        let value: Int?

        init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let number = try? container.decode(Int.self) {
                value = number
            } else {
                let text = try container.decode(String.self)
                value = Int(text.hasPrefix("i") ? String(text.dropFirst()) : text)
            }
        }
    }

    func ideaID() throws(ToolFailure) -> Int {
        guard let id = id?.value else { throw ToolFailure("\(action) needs the idea's id, such as i3.") }
        return id
    }

    /// The state a marking action sets.
    func state() throws(ToolFailure) -> IdeaState {
        switch action {
            case "acknowledge", "reopen": return .acknowledged
            case "fulfil", "fulfill": return .fulfilled
            case "dismiss": return .dismissed
            default:
                throw ToolFailure("There is no action \(action): list, show, acknowledge, fulfil, dismiss, reopen.")
        }
    }
}
