internal import AemiJSON

/// Decodes Anthropic Messages streaming events into ``ModelEvent``s, one SSE event at a time.
///
/// Each event's JSON is parsed exactly once. `ping` is a keep-alive and produces nothing; any other event,
/// delta or block type this decoder does not know produces ``ModelEvent/unrecognized(event:type:)``.
public struct AnthropicStreamDecoder: Sendable {
    /// A decoder at the start of a response.
    public init() {}

    /// Decodes one event, appending what it means to `events`.
    /// - Throws: ``AnthropicStreamError/provider(_:)`` for an `error` event, or
    ///   ``AnthropicStreamError/malformed(event:)`` when the data does not match the event.
    public func decode(_ frame: SSEEvent, into events: inout [ModelEvent]) throws(AnthropicStreamError) {
        let wire: WireEvent
        do {
            wire = try AemiJSON.JSONDecoder().decode(WireEvent.self, from: frame.data)
        } catch {
            throw .malformed(event: frame.name)
        }
        guard let event = try wire.modelEvent(named: frame.name) else { return }
        events.append(event)
    }
}

// MARK: - Wire shapes
