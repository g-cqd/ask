public import Foundation

/// The ideas as the model and the person read them: one line an idea, its text on that line with its line breaks as spaces.
extension IdeaList {
    /// `i3 [new] 2026-11-01 14:05 what if the sidebar folded?`.
    public func line(_ idea: Idea, in zone: TimeZone = .current) -> String {
        let words = idea.text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
        return
            "\(idea.name) [\(idea.state.rawValue)] \(Self.stamp(idea.made, in: zone)) \(words.joined(separator: " "))"
    }

    /// The open ideas, or every one with `all`; and how many were left out.
    public func listing(all: Bool, in zone: TimeZone = .current) -> String {
        guard !ideas.isEmpty else { return "No ideas yet." }
        let shown = all ? ideas : ideas.filter(\.state.isOpen)
        var lines = shown.map { line($0, in: zone) }
        if lines.isEmpty { lines.append("Every idea is fulfilled or dismissed.") }
        if ideas.count > shown.count {
            lines.append("(\(ideas.count - shown.count) fulfilled or dismissed, not shown)")
        }
        return lines.joined(separator: "\n")
    }

    /// `2026-11-01 14:05`.
    static func stamp(_ seconds: Int, in zone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let parts = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: Date(timeIntervalSince1970: Double(seconds))
        )
        let two = { (value: Int?) in
            let text = String(value ?? 0)
            return text.count < 2 ? "0" + text : text
        }
        return "\(parts.year ?? 0)-\(two(parts.month))-\(two(parts.day)) \(two(parts.hour)):\(two(parts.minute))"
    }
}
