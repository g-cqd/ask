/// What the picker lists for what was typed (roadmap 0048): a name that starts with it first, then a name that contains it, then a
/// summary that mentions it, each group in the order the commands were given. Prefix first is a rule because the prototype's first
/// version ranked `explorer` above `reviewer` for `re`. Matching ignores case; an empty query lists everything.
enum PickerRanking {
    /// `commands` that match `query`, best first.
    static func rank(_ commands: [SlashCommand], query: String) -> [SlashCommand] {
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
