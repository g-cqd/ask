internal import AemiJSON

// The deltas and the blocks they fill; apart from ResponsesStreamDecoder.swift to keep each file under
// the 250-line ceiling and the type body under 200 lines.
extension ResponsesStreamDecoder {
    // MARK: - Deltas

    /// The item a delta is for and its text, registering an item no `added` event announced; nil for an empty delta.
    mutating func delta(_ wire: ResponsesWireEvent, for kind: Kind) -> (id: String, text: String)? {
        guard let text = wire.delta, !text.isEmpty,
            let id = identities.resolve(wire.itemID, index: wire.outputIndex)
        else { return nil }
        if items[id] == nil { items[id] = Tracked(kind: kind) }
        return (id, text)
    }

    mutating func appendText(_ wire: ResponsesWireEvent, into events: inout [ModelEvent]) {
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

    mutating func appendThinking(_ wire: ResponsesWireEvent, into events: inout [ModelEvent]) {
        guard let (id, text) = delta(wire, for: .reasoning) else { return }
        let block = items[id]?.block ?? begin(id, .thinking, into: &events)
        if items[id]?.pendingBreak == true {
            events.append(.thinkingDelta(index: block, "\n\n"))
            items[id]?.pendingBreak = false
        }
        events.append(.thinkingDelta(index: block, text))
        items[id]?.wroteText = true
    }

    mutating func markBreak(_ id: String?) {
        if let id, items[id]?.wroteText == true { items[id]?.pendingBreak = true }
    }

    mutating func appendArguments(_ wire: ResponsesWireEvent, into events: inout [ModelEvent]) {
        guard let id = identities.resolve(wire.itemID, index: wire.outputIndex),
            let fragment = wire.delta, !fragment.isEmpty, let block = items[id]?.block
        else {
            return
        }
        items[id]?.sawArguments = true
        events.append(.toolInputDelta(index: block, fragment))
    }

    mutating func end(_ response: ResponsesWireEvent.Response) {
        let called = sawCall || (response.output ?? []).contains { $0.type == "function_call" }
        ending = Ending(
            stop: Self.stopReason(of: response, called: called, refused: sawRefusal),
            usage: response.usage?.tokens ?? TokenUsage()
        )
    }

    // MARK: - Blocks

    mutating func begin(_ id: String, _ kind: BlockKind, into events: inout [ModelEvent]) -> Int {
        let block = open(id, kind, into: &events)
        items[id]?.block = block
        return block
    }

    mutating func open(_ id: String, _ kind: BlockKind, into events: inout [ModelEvent]) -> Int {
        let block = nextBlock
        nextBlock += 1
        open.append(id)
        events.append(.blockStarted(index: block, kind))
        return block
    }

    mutating func close(_ id: String, into events: inout [ModelEvent]) {
        guard let block = items[id]?.block, let position = open.firstIndex(of: id) else { return }
        open.remove(at: position)
        events.append(.blockStopped(index: block))
    }
}
