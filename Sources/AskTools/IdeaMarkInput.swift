internal import AskAgentCore

/// One entry of a notes call's `changes`.
struct IdeaMarkInput: Decodable {
    let mark: IdeaPlanner.Mark

    init(from decoder: any Decoder) throws {
        let place = ToolInputError.entry
        let container = try decoder.container(keyedBy: RecordKey.self)
        // One tool, one word for it (ADR-0161): a mark is a `state`, as a task's is. Any other op would write a note, and is
        // said before the fields it brought are.
        guard try container.field("op", String.self) ?? "state" == "state" else {
            throw ToolInputError("\(place): a note takes op state only; notes are the person's to write.")
        }
        try container.only(["op", "ids", "state", "task"], in: place, for: "a change to notes")
        guard let ids = try container.refs("ids", prefix: "n", in: place), !ids.isEmpty else {
            throw ToolInputError("\(place): mark needs ids.")
        }
        let state: IdeaState
        switch try container.field("state", String.self) {
            case "acknowledged": state = .acknowledged
            case "fulfilled": state = .fulfilled
            case "dismissed": state = .dismissed
            default:
                throw ToolInputError(
                    "\(place): state is acknowledged, fulfilled or dismissed; notes are the person's to write."
                )
        }
        let task = try container.refs("task", prefix: "t", in: place)
        guard task == nil || task?.count == 1 else { throw ToolInputError("\(place): task takes one id.") }
        mark = IdeaPlanner.Mark(ideas: ids, state: state, task: task?.first)
    }
}
