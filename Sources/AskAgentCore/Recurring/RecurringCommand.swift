internal import Foundation

/// What `/loop` was asked (roadmap 0228): `/loop 5m TASK` adds, `/loop` lists, `/loop stop N` or `/loop stop all` removes.
public enum RecurringCommand: Sendable, Equatable {
    case list
    case add(every: Duration, prompt: String)
    case stop(Int)
    case stopAll
    case invalid(String)

    public static let usage =
        "/loop 10m TASK sends TASK every 10 minutes (s, m, h, d; at least 1 minute); /loop lists them; /loop stop N or /loop stop all."

    public static func parse(_ arguments: String) -> RecurringCommand {
        let words = arguments.split(whereSeparator: \.isWhitespace).map(String.init)
        guard let first = words.first else { return .list }
        if first.lowercased() == "stop" {
            guard words.count == 2 else { return .invalid(usage) }
            if words[1].lowercased() == "all" { return .stopAll }
            return Int(words[1]).map { .stop($0) } ?? .invalid(usage)
        }
        guard let every = interval(first) else { return .invalid(usage) }
        guard every >= RecurringPrompts.minimumInterval else {
            return .invalid("A loop runs at most once a minute. " + usage)
        }
        let prompt = words.dropFirst().joined(separator: " ")
        guard !prompt.isEmpty else { return .invalid("Say what to send. " + usage) }
        return .add(every: every, prompt: prompt)
    }

    /// `90s`, `10m`, `2h`, `1d` as a duration; nil for anything else.
    public static func interval(_ word: String) -> Duration? {
        guard let unit = word.last, let count = Int(word.dropLast()), count > 0, count <= 10_000 else { return nil }
        switch unit {
            case "s": return .seconds(count)
            case "m": return .seconds(count * 60)
            case "h": return .seconds(count * 3600)
            case "d": return .seconds(count * 86_400)
            default: return nil
        }
    }

    /// `10 min`, `2 h`, `1 d`, `90 s`.
    public static func describe(_ every: Duration) -> String {
        let seconds = Int(every.components.seconds)
        if seconds % 86_400 == 0 { return "\(seconds / 86_400) d" }
        if seconds % 3600 == 0 { return "\(seconds / 3600) h" }
        if seconds % 60 == 0 { return "\(seconds / 60) min" }
        return "\(seconds) s"
    }
}
