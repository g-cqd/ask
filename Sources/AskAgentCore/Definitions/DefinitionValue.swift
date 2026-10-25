/// A value in the head of a definition file (a skill's `SKILL.md`, an agent's Markdown or TOML): a scalar kept as the text it was written as, a
/// list, or a map that keeps the order its keys came in.
public indirect enum DefinitionValue: Sendable, Equatable {
    case text(String)
    case list([DefinitionValue])
    case map([DefinitionEntry])

    /// The scalar's text, or nil for a list or map.
    public var scalar: String? {
        if case .text(let text) = self { return text }
        return nil
    }

    /// Every scalar inside the value, in order, however deeply it is nested: what a field that should be a list of words yields whether it
    /// was written as a string, a flow list or a block list.
    public var scalars: [String] {
        switch self {
            case .text(let text): [text]
            case .list(let items): items.flatMap(\.scalars)
            case .map(let entries): entries.flatMap { $0.value.scalars }
        }
    }
}
