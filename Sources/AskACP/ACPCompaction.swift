internal import AemiJSON
internal import AskTUI

/// A compaction as ACP shows it (ACP v1, Prompt Turn, "Session compaction"): one entity of the timeline under an id of ask's,
/// begun and then ended, or told once when it is already done.
enum ACPCompaction {
    /// `compaction_update`: the compaction `id` began.
    static func began(_ id: String) -> JSONValue {
        ["sessionUpdate": "compaction_update", "compactionId": .string(id), "status": "in_progress"]
    }

    /// `compaction_update`: the compaction `id` ended as `status`, with `text`: what it kept, or why it failed.
    static func ended(_ id: String, _ status: Transcript.ToolStatus, text: String) -> JSONValue {
        var update: OrderedDictionary<String, JSONValue> = [
            "sessionUpdate": "compaction_update", "compactionId": .string(id)
        ]
        switch status {
            case .succeeded:
                update["status"] = "completed"
                if !text.isEmpty { update["summary"] = [["type": "text", "text": .string(text)]] }
            case .failed:
                update["status"] = "failed"
                if !text.isEmpty { update["error"] = .string(text) }
            case .interrupted: update["status"] = "cancelled"
            case .running: update["status"] = "in_progress"
        }
        return .object(update)
    }

    /// `compaction_update`: the compaction `id` was stopped before it ended.
    static func cancelled(_ id: String) -> JSONValue { ended(id, .interrupted, text: "") }
}
