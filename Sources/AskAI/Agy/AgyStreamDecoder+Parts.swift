internal import AemiJSON

extension AgyStreamDecoder {
    mutating func handle(_ part: JSON, into events: inout [ModelEvent]) {
        if part["functionCall"].isObject {
            call(part, into: &events)
        } else if let text = part["text"].string {
            append(text, run: part["thought"].bool == true ? .thinking : .text, into: &events)
        } else {
            var unknown: String?
            part.forEachMember { name, _ in
                if unknown == nil, name != "thought", name != "thoughtSignature" { unknown = String(name) }
            }
            if let unknown { events.append(.unrecognized(event: "part", type: unknown)) }
        }
    }

    private mutating func append(_ text: String, run: Run, into events: inout [ModelEvent]) {
        guard !text.isEmpty else { return }
        if let open, open.run == run {
            events.append(Self.delta(run, open.index, text))
            return
        }
        let lead = held.flatMap { $0.run == run ? $0.text : nil } ?? ""
        if text.allSatisfy(\.isWhitespace) {
            held = (run, lead + text)
            return
        }
        closeOpen(into: &events)
        held = nil
        let index = begin(run == .text ? .text : .thinking, into: &events)
        open = (run, index)
        events.append(Self.delta(run, index, lead + text))
    }

    private mutating func call(_ part: JSON, into events: inout [ModelEvent]) {
        closeOpen(into: &events)
        held = nil
        sawCall = true
        let wire = part["functionCall"]
        var id = wire["id"].string ?? ""
        if id.isEmpty || !callIDs.insert(id).inserted {
            id = ToolCallID.generated()
            callIDs.insert(id)
        }
        if let signature = part["thoughtSignature"].string, !signature.isEmpty {
            let carrier = begin(.thinking, into: &events)
            events.append(
                .signatureDelta(
                    index: carrier,
                    ReasoningProvenance.mark(scheme: Self.schemePrefix + model, payload: signature)))
            events.append(.blockStopped(index: carrier))
        }
        let index = begin(.toolUse(id: id, name: wire["name"].string ?? ""), into: &events)
        let args = wire["args"]
        let json = args.isObject ? (try? String(decoding: args.encodedBytes(), as: UTF8.self)) ?? "{}" : "{}"
        events.append(.toolInputDelta(index: index, json))
        events.append(.blockStopped(index: index))
    }

    private mutating func begin(_ kind: BlockKind, into events: inout [ModelEvent]) -> Int {
        let index = nextBlock
        nextBlock += 1
        events.append(.blockStarted(index: index, kind))
        return index
    }

    mutating func closeOpen(into events: inout [ModelEvent]) {
        guard let open else { return }
        events.append(.blockStopped(index: open.index))
        self.open = nil
    }

    private static func delta(_ run: Run, _ index: Int, _ text: String) -> ModelEvent {
        run == .text ? .textDelta(index: index, text) : .thinkingDelta(index: index, text)
    }
}
