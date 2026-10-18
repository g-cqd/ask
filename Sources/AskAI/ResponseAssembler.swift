/// One block of a complete assistant response.
public enum ContentBlock: Sendable, Equatable {
    case text(String)
    /// Reasoning, with the signature that must accompany it when sent back.
    case thinking(text: String, signature: String)
    case redactedThinking(data: String)
    /// A tool call with its arguments, validated as one JSON object.
    case toolCall(id: String, name: String, input: JSONObject)
    /// A block type the decoder did not know, kept so the response is not silently shortened.
    case unrecognized(type: String)
}

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

/// Folds ``ModelEvent``s into an ``AssembledResponse``, refusing any order the protocol does not allow.
public struct ResponseAssembler: Sendable {
    /// A block being streamed. Fields are appended in place, so a long block costs amortized O(1) per delta.
    private struct Block: Sendable {
        enum Kind: Sendable {
            case text, thinking
            case redactedThinking(String)
            case toolCall(id: String, name: String)
            case unrecognized(String)
        }

        let kind: Kind
        var text = ""
        var signature = ""
        var input: [UInt8] = []
        var validatedInput: JSONObject?
    }

    private var response: AssembledResponse?
    private var blocks: [Int: Block] = [:]
    private var open: Set<Int> = []
    private var stopped = false

    /// An assembler waiting for `messageStarted`.
    public init() {}

    /// Applies one event.
    /// - Throws: a ``ResponseAssemblyError`` naming the first event out of order.
    public mutating func apply(_ event: ModelEvent) throws(ResponseAssemblyError) {
        guard !stopped else { throw .eventAfterStop }
        if case .messageStarted(let id, let model, let usage) = event {
            guard response == nil else { throw .startedTwice }
            response = AssembledResponse(
                id: id, model: model, blocks: [], stopReason: nil, usage: usage, unrecognized: [])
            return
        }
        guard response != nil else { throw .notStarted }
        switch event {
            case .messageStarted: return
            case .blockStarted(let index, let kind): try start(index, kind)
            case .blockStopped(let index): try stop(index)
            case .messageDelta(let reason, let usage): applyDelta(reason, usage)
            case .messageStopped: stopped = true
            case .unrecognized(let name, let type): response?.unrecognized.append("\(name)/\(type)")
            default: try append(event)
        }
    }

    /// The assembled response.
    /// - Throws: ``ResponseAssemblyError/incomplete(openBlocks:)`` unless the stream reached `messageStopped`
    ///   with every block stopped.
    public func finish() throws(ResponseAssemblyError) -> AssembledResponse {
        guard stopped, open.isEmpty, var response else { throw .incomplete(openBlocks: open.sorted()) }
        response.blocks = blocks.keys.sorted().compactMap { blocks[$0].map(Self.finished) }
        return response
    }

    // MARK: - Steps

    private mutating func start(_ index: Int, _ kind: BlockKind) throws(ResponseAssemblyError) {
        guard blocks[index] == nil else { throw .blockStartedTwice(index: index) }
        open.insert(index)
        switch kind {
            case .text: blocks[index] = Block(kind: .text)
            case .thinking: blocks[index] = Block(kind: .thinking)
            case .redactedThinking(let data): blocks[index] = Block(kind: .redactedThinking(data))
            case .toolUse(let id, let name): blocks[index] = Block(kind: .toolCall(id: id, name: name))
            case .unrecognized(let type): blocks[index] = Block(kind: .unrecognized(type))
        }
    }

    private mutating func stop(_ index: Int) throws(ResponseAssemblyError) {
        guard open.remove(index) != nil, let block = blocks[index] else { throw .unknownBlock(index: index) }
        guard case .toolCall(let id, _) = block.kind else { return }
        do {
            blocks[index]?.validatedInput = try JSONObject(
                validating: block.input.isEmpty ? Array("{}".utf8) : block.input)
        } catch {
            throw .invalidToolInput(id: id)
        }
    }

    private mutating func applyDelta(_ reason: StopReason?, _ usage: TokenUsage) {
        guard var current = response else { return }
        current.stopReason = reason ?? current.stopReason
        // Deltas carry cumulative counts; a field a delta omits keeps the start's value.
        current.usage.input = usage.input ?? current.usage.input
        current.usage.output = usage.output ?? current.usage.output
        current.usage.cacheRead = usage.cacheRead ?? current.usage.cacheRead
        current.usage.cacheCreation = usage.cacheCreation ?? current.usage.cacheCreation
        response = current
    }

    private mutating func append(_ event: ModelEvent) throws(ResponseAssemblyError) {
        let index: Int
        switch event {
            case .textDelta(let at, _), .thinkingDelta(let at, _), .signatureDelta(let at, _),
                .toolInputDelta(let at, _):
                index = at
            default: return
        }
        guard let kind = blocks[index]?.kind else { throw .unknownBlock(index: index) }
        guard open.contains(index) else { throw .mismatchedDelta(index: index) }
        switch (kind, event) {
            case (.text, .textDelta(_, let more)), (.thinking, .thinkingDelta(_, let more)):
                blocks[index]?.text.append(more)
            case (.thinking, .signatureDelta(_, let more)): blocks[index]?.signature.append(more)
            case (.toolCall, .toolInputDelta(_, let more)): blocks[index]?.input.append(contentsOf: more.utf8)
            default: throw .mismatchedDelta(index: index)
        }
    }

    private static func finished(_ block: Block) -> ContentBlock {
        switch block.kind {
            case .text: .text(block.text)
            case .thinking: .thinking(text: block.text, signature: block.signature)
            case .redactedThinking(let data): .redactedThinking(data: data)
            case .toolCall(let id, let name):
                // Unreachable: finish() requires every block stopped, and stopping a tool block validates it.
                .toolCall(id: id, name: name, input: block.validatedInput ?? JSONObject.empty)
            case .unrecognized(let type): .unrecognized(type: type)
        }
    }
}
