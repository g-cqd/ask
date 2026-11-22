public import AskAI

/// What one response cost, held beside its entry (roadmap 0239) so it is read without reading the payload, which may be left in the
/// file. A class, so an entry carries a reference, 8 bytes, rather than 80 bytes inline on every entry, responses or not.
public final class ResponseSpend: Sendable {
    public let usage: TokenUsage
    public let model: String

    init(usage: TokenUsage, model: String) {
        self.usage = usage
        self.model = model
    }
}
