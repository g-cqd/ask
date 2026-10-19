/// Token counts. A field the provider did not report is nil, never zero.
public struct TokenUsage: Sendable, Equatable {
    public var input: Int?
    public var output: Int?
    public var cacheRead: Int?
    public var cacheCreation: Int?

    /// Usage with these counts.
    public init(input: Int? = nil, output: Int? = nil, cacheRead: Int? = nil, cacheCreation: Int? = nil) {
        self.input = input
        self.output = output
        self.cacheRead = cacheRead
        self.cacheCreation = cacheCreation
    }
}

extension TokenUsage {
    /// Usage as an OpenAI protocol reports it, in neutral terms: `input` counts only the prompt tokens the server did
    /// not read from its cache, as Anthropic reports it, so the two providers' figures mean the same thing.
    init(prompt: Int?, completion: Int?, cached: Int?) {
        self.init(input: prompt.map { Swift.max(0, $0 - (cached ?? 0)) }, output: completion, cacheRead: cached)
    }
}
