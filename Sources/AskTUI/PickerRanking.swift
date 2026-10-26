/// What the picker lists for what was typed (roadmap 0048): a name that starts with it first, then a name that contains it, then a
/// summary that mentions it, each group in the order the commands were given. Prefix first is a rule because the prototype's first
/// version ranked `explorer` above `reviewer` for `re`. Matching ignores case; an empty query lists everything.
enum PickerRanking {
    /// `commands` that match `query`, best first.
    static func rank(_ commands: [SlashCommand], query: String) -> [SlashCommand] {
        // @dl:accept -- the two rankings (commands by name and summary, choices by label and gloss) share a shape over different row types; a protocol would cost more than it saves
        let needle = query.lowercased()
        guard !needle.isEmpty else { return commands }
        var prefixes: [SlashCommand] = []
        var names: [SlashCommand] = []
        var summaries: [SlashCommand] = []
        for command in commands {
            let name = command.name.lowercased()
            if name.hasPrefix(needle) {
                prefixes.append(command)
            } else if name.contains(needle) {
                names.append(command)
            } else if command.summary.lowercased().contains(needle) {
                summaries.append(command)
            }
        }
        return prefixes + names + summaries
    }
}

extension PickerRanking {
    /// The `rows` of a command's list that match `query`, best first: a label that starts with it, then one that contains it, then an
    /// argument or a gloss that does. Words of the query may come in any order, so `opus 5` finds `claude-opus-5-5`.
    static func rank(_ rows: [ChoiceRow], query: String) -> [ChoiceRow] {
        let words = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return rows }
        var prefixes: [ChoiceRow] = []
        var labels: [ChoiceRow] = []
        var others: [ChoiceRow] = []
        for row in rows {
            let label = row.label.lowercased()
            let rest = (row.arguments + " " + row.detail).lowercased()
            guard words.allSatisfy({ label.contains($0) || rest.contains($0) }) else { continue }
            if words.count == 1, label.hasPrefix(words[0]) || row.arguments.lowercased().hasPrefix(words[0]) {
                prefixes.append(row)
            } else if words.allSatisfy({ label.contains($0) }) {
                labels.append(row)
            } else {
                others.append(row)
            }
        }
        return prefixes + labels + others
    }
}
