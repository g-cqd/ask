internal import AskAgentCore

/// A `tasks` call (ADR-0161): on the task list, or on the person's notes. One tool reaches both, being two lists of one store
/// and one shape (ADR-0141).
public enum ListsRequest: Decodable, Sendable {
    case tasks(TaskRequest)
    case notes(IdeaRequest)

    /// What says which list a call is on when it does not say: read before either list's own decoder refuses what it does not take.
    private struct Hint: Decodable {
        struct Entry: Decodable {
            let ids: String?
            let view: String?
        }
        let changes: [Entry]?
        let read: Entry?

        /// A note's id, or the view only notes have: nothing of the tasks starts with `n` or is `new`.
        var meansNotes: Bool {
            read?.view == "new" || ((changes ?? []) + [read].compactMap(\.self)).contains { $0.ids?.first == "n" }
        }
    }

    public init(from decoder: any Decoder) throws {
        let list = try decoder.container(keyedBy: RecordKey.self).field("list", String.self)
        switch list {
            case "notes": self = .notes(try IdeaRequest(from: decoder))
            case "tasks": self = .tasks(try TaskRequest(from: decoder))
            // Not refused for leaving `list` out (ADR-0161): n3 can only be a note, and saying so costs the model a call.
            case nil where (try? Hint(from: decoder))?.meansNotes == true: self = .notes(try IdeaRequest(from: decoder))
            case nil: self = .tasks(try TaskRequest(from: decoder))
            default: throw ToolInputError("the call: list is tasks or notes.")
        }
    }
}
