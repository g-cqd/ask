public import AskAI

extension TokenUsage {
    /// Both usages added, a count neither reported staying unreported: a summary's parts, a turn's responses, a task's turns.
    public func adding(_ other: TokenUsage) -> TokenUsage {
        func add(_ one: Int?, _ other: Int?) -> Int? { one == nil && other == nil ? nil : (one ?? 0) + (other ?? 0) }
        return TokenUsage(
            input: add(input, other.input),
            output: add(output, other.output),
            cacheRead: add(cacheRead, other.cacheRead),
            cacheCreation: add(cacheCreation, other.cacheCreation)
        )
    }
}
