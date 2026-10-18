/// Why a stream did not assemble. Each names the first event that broke the protocol's order.
public enum ResponseAssemblyError: Error, Sendable, Equatable {
    case notStarted
    case startedTwice
    case unknownBlock(index: Int)
    case blockStartedTwice(index: Int)
    /// A delta that does not fit its block's kind, or arrived after the block stopped.
    case mismatchedDelta(index: Int)
    case invalidToolInput(id: String)
    /// The stream ended before `messageStopped`; `openBlocks` were still streaming.
    case incomplete(openBlocks: [Int])
    case eventAfterStop
}
