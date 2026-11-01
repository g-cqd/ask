internal import AskAgentCore

/// What a `tasks` call asks (ADR-0140): ids as `t3` or `3`, links as one id or a list.
public struct TaskRequest: Decodable, Sendable {
    let action: String
    let id: TaskIDs?
    let title: String?
    let detail: String?
    let all: Bool?
    let before: TaskIDs?
    let after: TaskIDs?
    let blockedBy: TaskIDs?
    let related: TaskIDs?

    enum CodingKeys: String, CodingKey {
        case action, id, title, detail, all, before, after, related
        case blockedBy = "blocked_by"
    }

    /// One id or several, each `t3` or `3`.
    struct TaskIDs: Decodable, Sendable {
        let values: [Int]

        init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let number = try? container.decode(Int.self) {
                values = [number]
            } else if let text = try? container.decode(String.self) {
                values = [try Self.id(text, decoder)]
            } else {
                values = try container.decode([String].self).map { try Self.id($0, decoder) }
            }
        }

        private static func id(_ text: String, _ decoder: any Decoder) throws -> Int {
            guard let id = Int(text.hasPrefix("t") ? String(text.dropFirst()) : text) else {
                throw DecodingError.dataCorrupted(
                    .init(codingPath: decoder.codingPath, debugDescription: "task ids look like t3")
                )
            }
            return id
        }
    }

    func taskID() throws(ToolFailure) -> Int {
        guard let id = id?.values.first else { throw ToolFailure("\(action) needs the task's id, such as t3.") }
        return id
    }

    /// The change an action on task `id` asks for.
    func change(for id: Int) throws(ToolFailure) -> TaskChange {
        switch action {
            case "edit": return .edit(id: id, title: title, detail: detail)
            case "start": return .state(id: id, .inProgress)
            case "done": return .state(id: id, .done)
            case "reopen": return .state(id: id, .open)
            case "remove": return .remove(id: id)
            case "move":
                if let before = before?.values.first { return .move(id: id, before: before) }
                if let after = after?.values.first { return .move(id: id, after: after) }
                throw ToolFailure("move needs before or after another task's id.")
            case "link", "unlink":
                let (link, targets) =
                    blockedBy.map { (TaskLink.blockedBy, $0.values) } ?? (.related, related?.values ?? [])
                guard let target = targets.first else { throw ToolFailure("\(action) needs blocked_by or related.") }
                return action == "link" ? .link(id: id, link, target: target) : .unlink(id: id, link, target: target)
            default:
                throw ToolFailure(
                    "There is no action \(action): list, show, add, edit, start, done, reopen, remove, move, link, unlink."
                )
        }
    }
}
