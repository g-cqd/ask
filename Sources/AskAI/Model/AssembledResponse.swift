/// A complete assistant response.
public struct AssembledResponse: Sendable, Equatable {
    public var id: String
    public var model: String
    /// The blocks, in index order.
    public var blocks: [ContentBlock]
    public var stopReason: StopReason?
    public var usage: TokenUsage
    /// Events and deltas that were not understood, as `event/type`, for diagnostics.
    public var unrecognized: [String]

    /// A response with these fields.
    public init(
        id: String, model: String, blocks: [ContentBlock], stopReason: StopReason?, usage: TokenUsage,
        unrecognized: [String]
    ) {
        self.id = id
        self.model = model
        self.blocks = blocks
        self.stopReason = stopReason
        self.usage = usage
        self.unrecognized = unrecognized
    }
}
