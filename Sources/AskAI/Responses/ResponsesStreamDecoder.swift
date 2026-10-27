internal import AemiJSON

/// Turns a Responses API stream into ``ModelEvent``s, one server-sent event at a time.
///
/// The protocol is made of items (reasoning, message, function call), each announced by `output_item.added`, fed by
/// deltas that name it by `item_id`, and closed by `output_item.done`, which carries the whole item. The decoder numbers
/// blocks in the order they start, using `output_index` when supplied and `item_id` when it is not (llama.cpp).
/// Rotating IDs on an indexed item must not turn its final text echo into another reply. A text or reasoning block starts at its first real text, so an item with nothing to show makes no block
/// (whitespace-only text would be refused by a provider such as Anthropic if a session later moved to it).
///
/// A reasoning item that arrives with `encrypted_content` is kept whole behind a provenance marker so it can be
/// replayed to the protocol that issued it, and to no other (ADR-0033). Usage and the stop reason come with the
/// terminal event, so the end of the response is reported when the stream ends.
public struct ResponsesStreamDecoder: ModelEventDecoding {
    /// The provenance scheme a reasoning item is stored under.
    static let scheme = "responses"

    private enum Kind { case reasoning, message, call, other }

    private struct Tracked {
        var kind: Kind
        var block: Int?
        var held = ""
        var wroteText = false
        var sawArguments = false
        var pendingBreak = false
    }

    private struct Ending {
        var stop: StopReason
        var usage: TokenUsage
    }

    private var started = false
    private var nextBlock = 0
    private var items: [String: Tracked] = [:]
    private var identities = ResponsesItemIdentity()
    private var open: [String] = []
    private var sawCall = false
    private var sawRefusal = false
    private var ending: Ending?

    /// A decoder at the start of a response.
    public init() {}

    /// Decodes one event, appending what it means to `events`.
    /// - Throws: ``OpenAIStreamError/provider(_:)`` for a failed response or an error event,
    ///   ``OpenAIStreamError/malformed`` for data that is not this protocol's JSON.
    public mutating func decode(_ frame: SSEEvent, into events: inout [ModelEvent]) throws(OpenAIStreamError) {
        let wire: ResponsesWireEvent
        do { wire = try AemiJSON.JSONDecoder().decode(ResponsesWireEvent.self, from: frame.data) } catch {
            throw .malformed
        }
        if wire.type == "error" { throw .provider(Self.failure(code: wire.code, message: wire.message ?? "")) }
        if wire.type == "response.failed" {
            let error = wire.response?.error
            throw .provider(Self.failure(code: error?.code, message: error?.message ?? "the response failed"))
        }
        if !started {
            started = true
            let response = wire.response
            events.append(.messageStarted(id: response?.id ?? "", model: response?.model ?? "", usage: TokenUsage()))
        }
        switch wire.type {
            case "response.output_item.added":
                if let item = wire.item { register(item, at: wire.outputIndex, into: &events) }
            case "response.output_item.done":
                if let item = wire.item { finish(item, at: wire.outputIndex, into: &events) }
            case "response.output_text.delta": appendText(wire, into: &events)
            case "response.refusal.delta":
                sawRefusal = true
                appendText(wire, into: &events)
            case "response.reasoning_text.delta", "response.reasoning_summary_text.delta":
                appendThinking(wire, into: &events)
            case "response.reasoning_summary_part.added":
                markBreak(identities.resolve(wire.itemID, index: wire.outputIndex))
            case "response.function_call_arguments.delta": appendArguments(wire, into: &events)
            case "response.completed", "response.incomplete": if let response = wire.response { end(response) }
            default:
                _ = identities.resolve(wire.itemID, index: wire.outputIndex)
                if !Self.quiet.contains(wire.type) {
                    events.append(.unrecognized(event: frame.name, type: wire.type))
                }
        }
    }

    /// Closes every block still open and ends the response.
    /// - Throws: ``OpenAIStreamError/unfinished`` when no terminal event arrived, which means the stream was cut off.
    public mutating func finish(into events: inout [ModelEvent]) throws(OpenAIStreamError) {
        guard started, let ending else { throw .unfinished }
        for id in open { if let block = items[id]?.block { events.append(.blockStopped(index: block)) } }
        open.removeAll()
        events.append(.messageDelta(stopReason: ending.stop, usage: ending.usage))
        events.append(.messageStopped)
    }

    /// The server's reason in an error body: OpenAI's `{"error":{…}}`, which llama.cpp and Ollama share.
    public static func failure(inErrorBody body: [UInt8]) -> ProviderFailure? {
        OpenAIStreamDecoder.failure(inErrorBody: body)
    }

    // MARK: - Items

    private mutating func register(_ item: ResponsesWireEvent.Item, at index: Int?, into events: inout [ModelEvent]) {
        let id = identities.resolve(item.id, index: index) ?? "item-\(items.count)"
        guard items[id] == nil else { return }
        switch item.type {
            case "reasoning": items[id] = Tracked(kind: .reasoning)
            case "message": items[id] = Tracked(kind: .message)
            case "function_call":
                sawCall = true
                let call = item.callID.flatMap { $0.isEmpty ? nil : $0 } ?? ToolCallID.generated()
                var tracked = Tracked(kind: .call)
                tracked.block = open(id, .toolUse(id: call, name: item.name ?? ""), into: &events)
                items[id] = tracked
            default:
                var tracked = Tracked(kind: .other)
                tracked.block = open(id, .unrecognized(type: item.type), into: &events)
                items[id] = tracked
        }
    }

    private mutating func finish(_ item: ResponsesWireEvent.Item, at index: Int?, into events: inout [ModelEvent]) {
        register(item, at: index, into: &events)
        guard
            let id = identities.resolve(item.id, index: index)
                ?? items.keys.first(where: { items[$0]?.block == nil && items[$0]?.kind != .call }),
            let tracked = items[id]
        else { return }
        switch tracked.kind {
            case .reasoning: finishReasoning(id, item, into: &events)
            case .message: finishMessage(id, item, into: &events)
            case .call:
                let whole = item.arguments ?? ""
                if !tracked.sawArguments, !whole.isEmpty, let block = tracked.block {
                    events.append(.toolInputDelta(index: block, whole))
                }
            case .other: break
        }
        close(id, into: &events)
    }

    private mutating func finishReasoning(
        _ id: String, _ item: ResponsesWireEvent.Item, into events: inout [ModelEvent]
    ) {
        let summaries = (item.summary ?? []).map { $0.text ?? "" }
        if items[id]?.block == nil, !summaries.joined().isEmpty {
            events.append(
                .thinkingDelta(index: begin(id, .thinking, into: &events), summaries.joined(separator: "\n\n")))
        }
        guard let sealed = item.encryptedContent, !sealed.isEmpty else { return }
        let block = items[id]?.block ?? begin(id, .thinking, into: &events)
        let payload = Self.reasoningPayload(id: item.id ?? id, summaries: summaries, sealed: sealed)
        events.append(.signatureDelta(index: block, ReasoningProvenance.mark(scheme: Self.scheme, payload: payload)))
    }

    private mutating func finishMessage(_ id: String, _ item: ResponsesWireEvent.Item, into events: inout [ModelEvent])
    {
        guard items[id]?.wroteText != true else { return }
        let whole = (item.content ?? []).map { $0.text ?? "" }.joined()
        if !whole.allSatisfy(\.isWhitespace) {
            events.append(.textDelta(index: begin(id, .text, into: &events), whole))
            items[id]?.wroteText = true
        }
    }

    // MARK: - Deltas

    /// The item a delta is for and its text, registering an item no `added` event announced; nil for an empty delta.
    private mutating func delta(_ wire: ResponsesWireEvent, for kind: Kind) -> (id: String, text: String)? {
        guard let text = wire.delta, !text.isEmpty,
            let id = identities.resolve(wire.itemID, index: wire.outputIndex)
        else { return nil }
        if items[id] == nil { items[id] = Tracked(kind: kind) }
        return (id, text)
    }

    private mutating func appendText(_ wire: ResponsesWireEvent, into events: inout [ModelEvent]) {
        guard let (id, text) = delta(wire, for: .message), var tracked = items[id] else { return }
        if let block = tracked.block {
            events.append(.textDelta(index: block, text))
            return
        }
        guard !text.allSatisfy(\.isWhitespace) else {
            tracked.held += text
            items[id] = tracked
            return
        }
        let lead = tracked.held
        events.append(.textDelta(index: begin(id, .text, into: &events), lead + text))
        items[id]?.wroteText = true
        items[id]?.held = ""
    }

    private mutating func appendThinking(_ wire: ResponsesWireEvent, into events: inout [ModelEvent]) {
        guard let (id, text) = delta(wire, for: .reasoning) else { return }
        let block = items[id]?.block ?? begin(id, .thinking, into: &events)
        if items[id]?.pendingBreak == true {
            events.append(.thinkingDelta(index: block, "\n\n"))
            items[id]?.pendingBreak = false
        }
        events.append(.thinkingDelta(index: block, text))
        items[id]?.wroteText = true
    }

    private mutating func markBreak(_ id: String?) {
        if let id, items[id]?.wroteText == true { items[id]?.pendingBreak = true }
    }

    private mutating func appendArguments(_ wire: ResponsesWireEvent, into events: inout [ModelEvent]) {
        guard let id = identities.resolve(wire.itemID, index: wire.outputIndex),
            let fragment = wire.delta, !fragment.isEmpty, let block = items[id]?.block
        else {
            return
        }
        items[id]?.sawArguments = true
        events.append(.toolInputDelta(index: block, fragment))
    }

    private mutating func end(_ response: ResponsesWireEvent.Response) {
        let called = sawCall || (response.output ?? []).contains { $0.type == "function_call" }
        ending = Ending(
            stop: Self.stopReason(of: response, called: called, refused: sawRefusal),
            usage: response.usage?.tokens ?? TokenUsage())
    }

    // MARK: - Blocks

    private mutating func begin(_ id: String, _ kind: BlockKind, into events: inout [ModelEvent]) -> Int {
        let block = open(id, kind, into: &events)
        items[id]?.block = block
        return block
    }

    private mutating func open(_ id: String, _ kind: BlockKind, into events: inout [ModelEvent]) -> Int {
        let block = nextBlock
        nextBlock += 1
        open.append(id)
        events.append(.blockStarted(index: block, kind))
        return block
    }

    private mutating func close(_ id: String, into events: inout [ModelEvent]) {
        guard let block = items[id]?.block, let position = open.firstIndex(of: id) else { return }
        open.remove(at: position)
        events.append(.blockStopped(index: block))
    }
}
