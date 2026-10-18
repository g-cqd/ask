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
