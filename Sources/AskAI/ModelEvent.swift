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

/// What kind of content a block holds.
public enum BlockKind: Sendable, Equatable {
    case text
    case thinking
    /// Reasoning the provider withheld, returned verbatim on the next request.
    case redactedThinking(data: String)
    case toolUse(id: String, name: String)
    /// A block type this decoder does not know.
    case unrecognized(type: String)
}

/// Why the model stopped generating.
public enum StopReason: Sendable, Equatable {
    case endTurn, maxTokens, stopSequence, toolUse, pauseTurn, refusal, contextWindowExceeded
    /// A reason this decoder does not know, kept verbatim.
    case other(String)
}

extension StopReason {
    private static let names: [(StopReason, String)] = [
        (.endTurn, "end_turn"), (.maxTokens, "max_tokens"), (.stopSequence, "stop_sequence"), (.toolUse, "tool_use"),
        (.pauseTurn, "pause_turn"), (.refusal, "refusal"), (.contextWindowExceeded, "model_context_window_exceeded")
    ]

    /// The reason for its name on the wire; an unknown name is kept verbatim.
    public init(wire: String) {
        self = Self.names.first { $0.1 == wire }?.0 ?? .other(wire)
    }

    /// The reason's name on the wire, which sessions persist.
    public var wire: String {
        if case .other(let name) = self { return name }
        return Self.names.first { $0.0 == self }?.1 ?? ""
    }
}

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

/// A failure the provider reported. Each kind calls for a different response, so none collapse into a string.
public struct ProviderFailure: Error, Sendable, Equatable {
    /// The provider's classification.
    public enum Kind: Sendable, Equatable {
        case overloaded, rateLimited, authentication, permission, invalidRequest, notFound, requestTooLarge, server
        /// A kind this decoder does not know, kept verbatim.
        case other(String)
    }

    public let kind: Kind
    /// The provider's message, for the user.
    public let message: String

    /// A failure of this kind.
    public init(kind: Kind, message: String) {
        self.kind = kind
        self.message = message
    }
}
