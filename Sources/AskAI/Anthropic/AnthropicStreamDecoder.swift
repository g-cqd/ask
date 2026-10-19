internal import AemiJSON

/// Decodes Anthropic Messages streaming events into ``ModelEvent``s, one SSE event at a time.
///
/// Each event's JSON is parsed exactly once. `ping` is a keep-alive and produces nothing; any other event,
/// delta or block type this decoder does not know produces ``ModelEvent/unrecognized(event:type:)``.
public struct AnthropicStreamDecoder: ModelEventDecoding {
    /// A decoder at the start of a response.
    public init() {}

    /// Decodes one event, appending what it means to `events`.
    /// - Throws: ``AnthropicStreamError/provider(_:)`` for an `error` event, or
    ///   ``AnthropicStreamError/malformed(event:)`` when the data does not match the event.
    // @dl:accept -- every decoder wraps its JSON decode in the same four lines over a different wire type; a helper would only rename the repetition
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

    /// The provider's reason in an error body (`{"type":"error","error":{…}}`), if it has one.
    public static func failure(inErrorBody body: [UInt8]) -> ProviderFailure? {
        var events: [ModelEvent] = []
        do {
            try AnthropicStreamDecoder().decode(SSEEvent(name: "error", data: body), into: &events)
        } catch .provider(let failure) {
            return failure
        } catch {
            return nil
        }
        return nil
    }
}

// MARK: - Wire shapes
