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
        // Tool input is judged here, once the stop reason is known: a call cut off by the output limit or a full
        // window is dropped (the loop asks the model to continue), any other invalid input is refused.
        var kept: [ContentBlock] = []
        for index in blocks.keys.sorted() {
            guard let block = blocks[index] else { continue }
            if case .toolCall(let id, _) = block.kind, block.validatedInput == nil {
                guard response.stopReason == .maxTokens || response.stopReason == .contextWindowExceeded else {
                    throw .invalidToolInput(id: id)
                }
                continue
            }
            kept.append(Self.finished(block))
        }
        response.blocks = kept
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
        guard case .toolCall = block.kind else { return }
        // Invalid input leaves `validatedInput` nil; `finish` decides what that means once the stop reason is known.
        blocks[index]?.validatedInput = try? JSONObject(
            validating: block.input.isEmpty ? Array("{}".utf8) : block.input)
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
                // Unreachable with nil: finish() drops or refuses tool blocks whose input did not validate.
                .toolCall(id: id, name: name, input: block.validatedInput ?? JSONObject.empty)
            case .unrecognized(let type): .unrecognized(type: type)
        }
    }
}
