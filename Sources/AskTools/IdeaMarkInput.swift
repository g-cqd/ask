internal import AskAgentCore

/// One entry of a notes call's `changes`.
struct IdeaMarkInput: Decodable {
    let mark: IdeaPlanner.Mark

    init(from decoder: any Decoder) throws {
        let place = ToolInputError.entry
        let container = try decoder.container(keyedBy: RecordKey.self)
        try container.only(["ids", "state", "task"], in: place, for: "a change")
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
