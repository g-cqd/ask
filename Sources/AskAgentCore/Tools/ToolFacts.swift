/// What a tool did, typed, beside the prose the model reads (roadmap 0078): the screen shows these and never parses the prose.
/// Recorded with the result, so a resumed session shows the same header. Each fact is absent unless the tool knew it.
public struct ToolFacts: Sendable, Equatable {
    /// How many occurrences an edit replaced.
    public var replacements: Int?

    /// Facts with each one given, or none.
    public init(replacements: Int? = nil) { self.replacements = replacements }
}
