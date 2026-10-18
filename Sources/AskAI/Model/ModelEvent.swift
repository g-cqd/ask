/// One step of a streamed model response, independent of the provider's wire protocol.
public enum ModelEvent: Sendable, Equatable {
    /// The response began.
    case messageStarted(id: String, model: String, usage: TokenUsage)
    /// A content block began at `index`.
    case blockStarted(index: Int, BlockKind)
    /// More visible text for the block at `index`.
    case textDelta(index: Int, String)
    /// More reasoning text for the block at `index`.
    case thinkingDelta(index: Int, String)
    /// The opaque signature that must accompany the reasoning block when it is sent back.
    case signatureDelta(index: Int, String)
    /// More of a tool call's input. Fragments are not JSON on their own; their concatenation is.
    case toolInputDelta(index: Int, String)
    /// The block at `index` is complete.
    case blockStopped(index: Int)
    /// Why generation stopped, and the cumulative usage so far.
    case messageDelta(stopReason: StopReason?, usage: TokenUsage)
    /// The response is complete.
    case messageStopped
    /// An event or delta this decoder does not know. Reported so new protocol features are visible.
    case unrecognized(event: String, type: String)
}
