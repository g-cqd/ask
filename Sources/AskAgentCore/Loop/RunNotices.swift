/// What a run says to a person, in words (roadmap 0028): the same notice in the screen and in `ask -p`.
public enum RunNotices {
    /// What a compaction says, or nil when `event` is not one.
    public static func compaction(for event: AgentEvent) -> String? {
        switch event {
            case .compacted(let summary, _):
                "Compacted the conversation: earlier messages are now a \(summary.count)-character summary. "
                    + "The session file keeps them all."
            case .compactionFailed(let reason):
                "Could not compact (\(reason)); continuing with the whole conversation."
            default: nil
        }
    }

    /// What a retry says: why, how long ask waits, and which attempt comes next.
    public static func retry(attempt: Int, of total: Int, delay: Duration, reason: String) -> String {
        let milliseconds = delay.components.seconds * 1_000 + delay.components.attoseconds / 1_000_000_000_000_000
        let wait = milliseconds % 1_000 == 0 ? "\(milliseconds / 1_000) s" : "\(Double(milliseconds) / 1_000) s"
        return "\(reason); retrying in \(wait) (attempt \(attempt) of \(total))."
    }
}
