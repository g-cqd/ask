/// A change as one JSON object with a `kind`, so the record says what it is, and a later version can add kinds.
extension TaskChange: Codable {
    private enum Key: String, CodingKey {
        case kind, task, id, title, detail, state, before, after, link, target
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: Key.self)
        let kind = try container.decode(String.self, forKey: .kind)
        if kind == "add" {
            self = .add(try container.decode(SessionTask.self, forKey: .task))
            return
        }
        let id = try container.decode(Int.self, forKey: .id)
        switch kind {
            case "edit":
                self = .edit(
                    id: id,
                    title: try container.decodeIfPresent(String.self, forKey: .title),
                    detail: try container.decodeIfPresent(String.self, forKey: .detail)
                )
            case "state": self = .state(id: id, try container.decode(TaskState.self, forKey: .state))
            case "move":
                if let before = try container.decodeIfPresent(Int.self, forKey: .before) {
                    self = .place(id: id, next: before, after: false)
                } else {
                    self = .place(id: id, next: try container.decode(Int.self, forKey: .after), after: true)
                }
            case "link", "unlink":
                let link = try container.decode(TaskLink.self, forKey: .link)
                let target = try container.decode(Int.self, forKey: .target)
                self = kind == "link" ? .link(id: id, link, target: target) : .unlink(id: id, link, target: target)
            case "remove": self = .remove(id: id)
            default:
                throw DecodingError.dataCorruptedError(
                    forKey: .kind,
                    in: container,
                    debugDescription: "unknown kind \(kind)"
                )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: Key.self)
        switch self {
            case .add(let task):
                // @dl:accept -- an encoder's arms each write their own keys; alike in shape, the keys are the data
                try container.encode("add", forKey: .kind)
                try container.encode(task, forKey: .task)
            case .edit(let id, let title, let detail):
                try Self.head("edit", id, &container)
                try container.encodeIfPresent(title, forKey: .title)
                try container.encodeIfPresent(detail, forKey: .detail)
            case .state(let id, let state):
                // @dl:accept -- an encoder's arms each write their own keys; alike in shape, the keys are the data
                try Self.head("state", id, &container)
                try container.encode(state, forKey: .state)
            case .place(let id, let next, let after):
                try Self.head("move", id, &container)
                try container.encode(next, forKey: after ? .after : .before)
            case .link(let id, let link, let target), .unlink(let id, let link, let target):
                try Self.head(isLink ? "link" : "unlink", id, &container)
                try container.encode(link, forKey: .link)
                try container.encode(target, forKey: .target)
            case .remove(let id): try Self.head("remove", id, &container)
        }
    }

    /// What every change but `add` starts with: its kind and the task it changes.
    private static func head(_ kind: String, _ id: Int, _ container: inout KeyedEncodingContainer<Key>) throws {
        try container.encode(kind, forKey: .kind)
        try container.encode(id, forKey: .id)
    }

    private var isLink: Bool {
        if case .link = self { return true }
        return false
    }
}
