internal import AskAgentCore

/// One entry of `changes`.
struct TaskEditInput: Decodable {
    let edit: TaskEdit

    private static let fields: [String: Set<String>] = [
        "add": ["op", "title", "detail", "state", "tags", "blocked_by", "related"],
        "edit": ["op", "ids", "title", "detail", "tags"],
        "state": ["op", "ids", "state"],
        "move": ["op", "ids", "before"],
        // @dl:accept -- a memberwise initialiser or a field table reads like any other of its kind; the fields are the data
        "link": ["op", "ids", "blocked_by", "related"],
        "unlink": ["op", "ids", "blocked_by", "related"],
        "remove": ["op", "ids"]
    ]

    init(from decoder: any Decoder) throws {
        let place = ToolInputError.entry
        let container = try decoder.container(keyedBy: RecordKey.self)
        let op = try container.field("op", String.self) ?? ""
        guard let allowed = Self.fields[op] else {
            throw ToolInputError("\(place): op is add, edit, state, move, link, unlink or remove.")
        }
        try container.only(allowed, in: place, for: op)
        let read = Reader(container: container, place: place, op: op)
        edit = try read.edit()
    }

    private struct Reader {
        let container: KeyedDecodingContainer<RecordKey>
        let place: String
        let op: String

        func edit() throws -> TaskEdit {
            switch op {
                case "add": return .add(try draft())
                case "edit":
                    return .edit(
                        try one("ids"),
                        title: try container.field("title"),
                        detail: try container.field("detail"),
                        tags: try container.words("tags")
                    )
                case "state":
                    return .state(
                        try ids(),
                        try state() ?? { throw ToolInputError("\(place): state needs a state.") }()
                    )
                case "move": return .move(try one("ids"), try placement())
                case "remove": return .remove(try ids())
                default:
                    let blockedBy = try refs("blocked_by") ?? []
                    let related = try refs("related") ?? []
                    return op == "link"
                        ? .link(try ids(), blockedBy: blockedBy, related: related)
                        : .unlink(try ids(), blockedBy: blockedBy, related: related)
            }
        }

        private func draft() throws -> TaskDraft {
            guard let title = try container.field("title", String.self) else {
                throw ToolInputError("\(place): add needs a title.")
            }
            return TaskDraft(
                title: title,
                detail: try container.field("detail") ?? "",
                state: try state() ?? .open,
                tags: try container.words("tags") ?? [],
                blockedBy: try refs("blocked_by") ?? [],
                related: try refs("related") ?? []
            )
        }

        private func refs(_ name: String) throws -> [ListRef]? { try container.refs(name, prefix: "t", in: place) }

        private func ids() throws -> [ListRef] {
            guard let ids = try refs("ids"), !ids.isEmpty else { throw ToolInputError("\(place): \(op) needs ids.") }
            return ids
        }

        private func one(_ name: String) throws -> ListRef {
            guard let ids = try refs(name), ids.count == 1 else {
                throw ToolInputError("\(place): \(op) takes one id in \(name).")
            }
            return ids[0]
        }

        private func placement() throws -> TaskPlacement {
            let before = try container.field("before", String.self)
            if before == "end" { return .end }
            guard let before, let next = ListRef(before, prefix: "t") else {
                throw ToolInputError("\(place): move takes before: one id, or end.")
            }
            return .before(next)
        }

        private func state() throws -> TaskState? {
            guard let text = try container.field("state", String.self) else { return nil }
            switch text {
                case "open": return .open
                case "in_progress": return .inProgress
                case "done": return .done
                default: throw ToolInputError("\(place): state is open, in_progress or done.")
            }
        }
    }
}
