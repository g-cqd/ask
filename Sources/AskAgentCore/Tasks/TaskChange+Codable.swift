/// A change as one JSON object with a `kind`, so the record says what it is, and a later version can add kinds: one this build does not
/// know throws ``ListRecordError``.
extension TaskChange: Codable {
    private enum Key: String, CodingKey {
        case kind, task, id, title, detail, state, at, before, after, link, target, tags, changes
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: Key.self)
        let kind = try container.decode(String.self, forKey: .kind)
        switch kind {
            case "add": self = .add(try container.decode(SessionTask.self, forKey: .task))
            case "batch": self = .batch(try container.decode([TaskChange].self, forKey: .changes))
            case "edit", "state", "move", "link", "unlink", "remove", "tags":
                self = try Self.decode(kind, id: try container.decode(Int.self, forKey: .id), container)
            default: throw ListRecordError(kind: kind)
        }
    }

    private static func decode(_ kind: String, id: Int, _ container: KeyedDecodingContainer<Key>) throws -> TaskChange {
        switch kind {
            case "edit":
                return .edit(
                    id: id,
                    title: try container.decodeIfPresent(String.self, forKey: .title),
                    detail: try container.decodeIfPresent(String.self, forKey: .detail)
                )
            case "state":
                return .state(
                    id: id,
                    try container.decode(TaskState.self, forKey: .state),
                    at: try container.decodeIfPresent(Int.self, forKey: .at)
                )
            case "move":
                if let before = try container.decodeIfPresent(Int.self, forKey: .before) {
                    return .place(id: id, next: before, after: false)
                }
                return .place(id: id, next: try container.decode(Int.self, forKey: .after), after: true)
            case "link", "unlink":
                let link = try container.decode(TaskLink.self, forKey: .link)
                let target = try container.decode(Int.self, forKey: .target)
                return kind == "link" ? .link(id: id, link, target: target) : .unlink(id: id, link, target: target)
            case "tags": return .tags(id: id, try container.decode([String].self, forKey: .tags))
            default: return .remove(id: id)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: Key.self)
        switch self {
            case .add(let task):
                try container.encode("add", forKey: .kind)
                try container.encode(task, forKey: .task)
            case .batch(let changes):
                try container.encode("batch", forKey: .kind)
                try container.encode(changes, forKey: .changes)
            case .edit(let id, let title, let detail):
                try Self.head("edit", id, &container)
                try container.encodeIfPresent(title, forKey: .title)
                try container.encodeIfPresent(detail, forKey: .detail)
            case .state(let id, let state, let time):
                try Self.head("state", id, &container)
                try container.encode(state, forKey: .state)
                try container.encodeIfPresent(time, forKey: .at)
            case .place(let id, let next, let after):
                try Self.head("move", id, &container)
                try container.encode(next, forKey: after ? .after : .before)
            case .link(let id, let link, let target), .unlink(let id, let link, let target):
                try Self.head(isLink ? "link" : "unlink", id, &container)
                try container.encode(link, forKey: .link)
                try container.encode(target, forKey: .target)
            case .tags(let id, let tags):
                try Self.head("tags", id, &container)
                try container.encode(tags, forKey: .tags)
            case .remove(let id): try Self.head("remove", id, &container)
        }
    }

    /// What every change but `add` and `batch` starts with: its kind and the task it changes.
    private static func head(_ kind: String, _ id: Int, _ container: inout KeyedEncodingContainer<Key>) throws {
        try container.encode(kind, forKey: .kind)
        try container.encode(id, forKey: .id)
    }

    private var isLink: Bool {
        if case .link = self { return true }
        return false
    }
}
