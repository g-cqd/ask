/// A note's change as 0180 first wrote it, the layout Swift gives an enum: one key naming the case, holding its values (`_0` for an
/// unnamed one). The cases ADR-0141 added keep it; a key this build does not know throws ``ListRecordError``.
extension IdeaChange: Codable {
    public init(from decoder: any Decoder) throws {
        let outer = try decoder.container(keyedBy: RecordKey.self)
        guard outer.allKeys.count == 1, let key = outer.allKeys.first else { throw ListRecordError(kind: "?") }
        guard ["add", "edit", "state", "link", "remove", "batch"].contains(key.stringValue) else {
            throw ListRecordError(kind: key.stringValue)
        }
        let values = try outer.nestedContainer(keyedBy: RecordKey.self, forKey: key)
        let id = { () throws -> Int in try values.decode(Int.self, forKey: RecordKey("id")) }
        switch key.stringValue {
            case "add": self = .add(try values.decode(Idea.self, forKey: RecordKey("_0")))
            case "batch": self = .batch(try values.decode([IdeaChange].self, forKey: RecordKey("_0")))
            case "edit":
                self = .edit(
                    id: try id(),
                    text: try values.decode(String.self, forKey: RecordKey("text")),
                    at: try values.decode(Int.self, forKey: RecordKey("at"))
                )
            case "state": self = .state(id: try id(), try values.decode(IdeaState.self, forKey: RecordKey("_1")))
            case "remove": self = .remove(id: try id())
            default: self = .link(id: try id(), task: try values.decode(Int.self, forKey: RecordKey("task")))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var outer = encoder.container(keyedBy: RecordKey.self)
        switch self {
            case .add(let idea):
                // @dl:accept -- each case writes its own keys in the layout 0180 set; alike in shape, the keys are the data
                var values = outer.nestedContainer(keyedBy: RecordKey.self, forKey: RecordKey("add"))
                try values.encode(idea, forKey: RecordKey("_0"))
            case .batch(let changes):
                var values = outer.nestedContainer(keyedBy: RecordKey.self, forKey: RecordKey("batch"))
                try values.encode(changes, forKey: RecordKey("_0"))
            // @dl:accept -- each case writes its own keys in the layout 0180 set; alike in shape, the keys are the data
            case .edit(let id, let text, let time):
                var values = outer.nestedContainer(keyedBy: RecordKey.self, forKey: RecordKey("edit"))
                try values.encode(id, forKey: RecordKey("id"))
                try values.encode(text, forKey: RecordKey("text"))
                try values.encode(time, forKey: RecordKey("at"))
            // @dl:accept -- each case writes its own keys in the layout 0180 set; alike in shape, the keys are the data
            case .state(let id, let state):
                var values = outer.nestedContainer(keyedBy: RecordKey.self, forKey: RecordKey("state"))
                try values.encode(id, forKey: RecordKey("id"))
                try values.encode(state, forKey: RecordKey("_1"))
            // @dl:accept -- each case writes its own keys in the layout 0180 set; alike in shape, the keys are the data
            case .link(let id, let task):
                var values = outer.nestedContainer(keyedBy: RecordKey.self, forKey: RecordKey("link"))
                // @dl:accept -- each case writes its own keys in the layout 0180 set; alike in shape, the keys are the data
                try values.encode(id, forKey: RecordKey("id"))
                try values.encode(task, forKey: RecordKey("task"))
            // @dl:accept -- each case writes its own keys in the layout 0180 set; alike in shape, the keys are the data
            case .remove(let id):
                var values = outer.nestedContainer(keyedBy: RecordKey.self, forKey: RecordKey("remove"))
                try values.encode(id, forKey: RecordKey("id"))
        }
    }
}
