import AskAI

/// A provider's stream (`SSEDecoder`, then each provider's event decoder): bytes from the network. Promised: the events do not depend
/// on where the network cut the stream; an event past the limit is an error, never a trap; a frame a decoder does not understand is an
/// error or nothing.
let fuzzSSE: @Sendable ([UInt8]) -> Void = { bytes in
    guard let seed = bytes.first else { return }
    let stream = bytes.dropFirst()
    let limits = SSEDecoder.Limits(maximumEventBytes: 2048)

    func decode(_ chunks: [[UInt8]]) -> (events: [SSEEvent], failed: Bool) {
        var decoder = SSEDecoder(limits: limits)
        var events: [SSEEvent] = []
        for chunk in chunks {
            do { try chunk.withUnsafeBufferPointer { try decoder.feed($0.span, into: &events) } } catch {
                return (events, true)
            }
        }
        return (events, false)
    }

    let whole = decode([Array(stream)])
    let cut = decode(pieces(of: stream, seed: seed))
    if whole.failed != cut.failed || whole.events != cut.events {
        broken(
            "SSE: the events depend on where the stream was cut (\(whole.events.count) whole, \(cut.events.count) cut)"
        )
    }
    var anthropic: [ModelEvent] = []
    var responses = ResponsesStreamDecoder()
    var agy = AgyStreamDecoder()
    for event in whole.events {
        try? AnthropicStreamDecoder().decode(event, into: &anthropic)
        var other: [ModelEvent] = []
        try? responses.decode(event, into: &other)
        try? agy.decode(event, into: &other)
    }
}
