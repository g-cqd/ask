internal import Foundation

/// What the judge said of a goal (roadmap 0227): its reply's first word decides; anything else counts as not yet.
public enum GoalVerdict: Sendable, Equatable {
    case met(String)
    case notYet(String)
    case impossible(String)

    /// The verdict in `reply`: `MET`, `NOT YET: reason` or `IMPOSSIBLE: reason`, in any case, after quotes or a bullet.
    public static func parse(_ reply: String) -> GoalVerdict {
        let text = reply.trimmingCharacters(in: .whitespacesAndNewlines)
            .drop { "\"'`*-• ".contains($0) }
        let upper = text.uppercased()
        func reason(after word: String) -> String {
            String(text.dropFirst(word.count)).trimmingCharacters(in: CharacterSet(charactersIn: " :.-—*`\n\t"))
        }
        if upper.hasPrefix("NOT YET") { return .notYet(reason(after: "NOT YET")) }
        if upper.hasPrefix("IMPOSSIBLE") { return .impossible(reason(after: "IMPOSSIBLE")) }
        if upper.hasPrefix("MET") { return .met(reason(after: "MET")) }
        return .notYet(
            text.isEmpty ? "the judge gave no verdict" : "the judge's answer was unclear: " + String(text.prefix(200))
        )
    }

    /// What the judge is asked.
    public static func question(condition: String, recent: String) -> String {
        """
        You judge whether a coding agent has met a goal, from what its run shows below. You run nothing and read nothing else: \
        judge only from this text. Reply with exactly one line:
        MET: <the evidence>
        NOT YET: <what is still missing, as an instruction to the agent>
        IMPOSSIBLE: <why it cannot be met>

        GOAL:
        \(condition)

        WHAT THE RUN SHOWED (most recent last):
        \(recent)
        """
    }
}
