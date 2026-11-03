public import Foundation

/// The notes as the model and the person read them: one line a note, its text on that line with its line breaks as spaces.
extension IdeaList {
    /// `n3 [new] 2026-11-01 14:05 what if the sidebar folded? → t12`, the text on one line and cut at 120 characters.
    public func line(_ idea: Idea, in zone: TimeZone = .current) -> String {
        let words = idea.text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
        var text = words.joined(separator: " ")
        if text.count > ListLimits.ideaLineLength { text = String(text.prefix(ListLimits.ideaLineLength - 1)) + "…" }
        return "\(head(idea, in: zone)) \(text)\(became(idea))"
    }

    /// A note's head, then its text whole, once.
    public func whole(_ idea: Idea, in zone: TimeZone = .current) -> String {
        head(idea, in: zone) + became(idea) + "\n" + idea.text
    }

    /// Shows note `id` in full, or nil when there is none.
    public func showing(_ id: Int, in zone: TimeZone = .current) -> String? {
        idea(id).map { whole($0, in: zone) }
    }

    private func head(_ idea: Idea, in zone: TimeZone) -> String {
        "\(idea.name) [\(idea.state.rawValue)] \(Self.stamp(idea.made, in: zone))"
    }

    private func became(_ idea: Idea) -> String {
        idea.tasks.isEmpty ? "" : " → " + idea.tasks.map { "t\($0)" }.joined(separator: " ")
    }

    /// The open notes, or every one with `all`; and how many were left out.
    public func listing(all: Bool, in zone: TimeZone = .current) -> String {
        guard !ideas.isEmpty else { return "No notes yet." }
        let shown = all ? ideas : ideas.filter(\.state.isOpen)
        var lines = shown.map { line($0, in: zone) }
        if lines.isEmpty { lines.append("Every note is fulfilled or dismissed.") }
        if ideas.count > shown.count {
            lines.append("(\(ideas.count - shown.count) fulfilled or dismissed, not shown)")
        }
        return lines.joined(separator: "\n")
    }

    /// Searches all notes for `query`, returning matching lines.
    public func searching(_ query: String, in zone: TimeZone = .current) -> String {
        guard !ideas.isEmpty else { return "No notes yet." }
        let matches = ListSearch.rank(ideas, words: query) { [$0.text] }
        guard !matches.isEmpty else { return "No note matches." }
        return matches.map { line($0, in: zone) }.joined(separator: "\n")
    }

    static func stamp(_ seconds: Int, in zone: TimeZone) -> String { ListTime.stamp(seconds, in: zone) }
}
