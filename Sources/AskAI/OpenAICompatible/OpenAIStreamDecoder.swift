internal import AemiJSON

/// Turns an OpenAI-compatible chat-completions stream into ``ModelEvent``s, one SSE event at a time.
///
/// That protocol has no content blocks: reasoning, text and tool calls arrive as fields of a delta, interleaved, and
/// tool calls are keyed by their own index. The decoder keeps one text or reasoning block open at a time and one
/// block per tool call, numbering blocks in the order they begin, and closes them all when the stream ends, because
/// usage can arrive after the finish reason. Text that is only whitespace is held back until real text follows and
/// dropped if none does: servers send `""` or `"\n\n"` around a tool call, and a whitespace-only text block is one a
/// provider such as Anthropic refuses if the session later moves to it.
public struct OpenAIStreamDecoder: Sendable {
    private enum Scalar: Sendable {
        case text(Int)
        case thinking(Int)
    }

    private var started = false
    private var nextBlock = 0
    private var scalar: Scalar?
    private var heldWhitespace = ""
    private var toolBlocks: [Int: Int] = [:]
    private var toolOrder: [Int] = []
    private var stopReason: StopReason?
    private var usage = TokenUsage()

    /// A decoder at the start of a response.
    public init() {}

    /// Decodes one event, appending what it means to `events`.
    /// - Throws: ``OpenAIStreamError/provider(_:)`` for an error payload, ``OpenAIStreamError/malformed`` for data
    ///   that is not this protocol's JSON.
    public mutating func decode(_ frame: SSEEvent, into events: inout [ModelEvent]) throws(OpenAIStreamError) {
        if frame.data.elementsEqual("[DONE]".utf8) { return }
        let chunk: OpenAIWireChunk
        do {
            chunk = try AemiJSON.JSONDecoder().decode(OpenAIWireChunk.self, from: frame.data)
        } catch {
            throw .malformed
        }
        if let error = chunk.error {
            let status = if case .number(let code) = error.code { code } else { Int?.none }
            throw .provider(
                ProviderFailure(kind: .init(openAIType: error.type, status: status), message: error.message ?? ""))
        }
        if !started {
            started = true
            events.append(.messageStarted(id: chunk.id ?? "", model: chunk.model ?? "", usage: TokenUsage()))
        }
        if let reported = chunk.usage { usage = reported.tokens }
        for choice in chunk.choices ?? [] {
            if let delta = choice.delta { apply(delta, into: &events) }
            if let reason = choice.finishReason { stopReason = Self.stopReason(reason) }
        }
    }

    /// Closes every open block and ends the response.
    /// - Throws: ``OpenAIStreamError/unfinished`` when the stream never said why generation stopped, which means it
    ///   was cut off rather than finished.
    public mutating func finish(into events: inout [ModelEvent]) throws(OpenAIStreamError) {
        guard started, let stopReason else { throw .unfinished }
        closeScalar(into: &events)
        for block in toolOrder { events.append(.blockStopped(index: block)) }
        toolOrder.removeAll()
        events.append(.messageDelta(stopReason: stopReason, usage: usage))
        events.append(.messageStopped)
    }

    // MARK: - Deltas

    private mutating func apply(_ delta: OpenAIWireChunk.Delta, into events: inout [ModelEvent]) {
        if let reasoning = delta.reasoningText, !reasoning.isEmpty { appendReasoning(reasoning, into: &events) }
        if let content = delta.content, !content.isEmpty { appendText(content, into: &events) }
        for call in delta.toolCalls ?? [] { appendToolCall(call, into: &events) }
    }

    private mutating func appendReasoning(_ text: String, into events: inout [ModelEvent]) {
        if case .thinking(let block) = scalar {
            events.append(.thinkingDelta(index: block, text))
            return
        }
        closeScalar(into: &events)
        let block = openBlock(.thinking, into: &events)
        scalar = .thinking(block)
        events.append(.thinkingDelta(index: block, text))
    }

    private mutating func appendText(_ text: String, into events: inout [ModelEvent]) {
        if case .text(let block) = scalar {
            events.append(.textDelta(index: block, text))
            return
        }
        guard !text.allSatisfy(\.isWhitespace) else {
            heldWhitespace += text
            return
        }
        let lead = heldWhitespace
        closeScalar(into: &events)
        let block = openBlock(.text, into: &events)
        scalar = .text(block)
        events.append(.textDelta(index: block, lead + text))
    }

    private mutating func appendToolCall(_ call: OpenAIWireChunk.ToolCall, into events: inout [ModelEvent]) {
        closeScalar(into: &events)
        let wireIndex = call.index ?? 0
        let block: Int
        if let existing = toolBlocks[wireIndex] {
            block = existing
        } else {
            let id = call.id.flatMap { $0.isEmpty ? nil : $0 } ?? Self.generatedID()
            block = openBlock(.toolUse(id: id, name: call.function?.name ?? ""), into: &events)
            toolBlocks[wireIndex] = block
            toolOrder.append(block)
        }
        if let fragment = call.function?.arguments, !fragment.isEmpty {
            events.append(.toolInputDelta(index: block, fragment))
        }
    }

    // MARK: - Blocks

    private mutating func openBlock(_ kind: BlockKind, into events: inout [ModelEvent]) -> Int {
        let block = nextBlock
        nextBlock += 1
        events.append(.blockStarted(index: block, kind))
        return block
    }

    /// Ends the open text or reasoning block, and forgets whitespace no text followed.
    private mutating func closeScalar(into events: inout [ModelEvent]) {
        heldWhitespace = ""
        switch scalar {
            case .text(let block), .thinking(let block): events.append(.blockStopped(index: block))
            case nil: break
        }
        scalar = nil
    }

    /// A call id for a server that sent none, unique enough that a session cannot match a result to the wrong call.
    private static func generatedID() -> String {
        var random = SystemRandomNumberGenerator()
        return "call_" + String(random.next(), radix: 16)
    }

    private static func stopReason(_ wire: String) -> StopReason {
        switch wire {
            case "stop": .endTurn
            case "tool_calls", "function_call": .toolUse
            case "length": .maxTokens
            case "content_filter": .refusal
            default: .other(wire)
        }
    }
}
