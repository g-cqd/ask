internal import AemiJSON

/// Why an Anthropic stream ended in failure.
public enum AnthropicStreamError: Error, Sendable, Equatable {
    /// The provider sent an `error` event.
    case provider(ProviderFailure)
    /// An event's data was not the shape its name promises.
    case malformed(event: String)
}

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

/// Every field any event can carry, so each event is parsed once, whatever its type.
private struct WireEvent: Decodable {
    let type: String
    let index: Int?
    let message: Message?
    let contentBlock: Block?
    let delta: Delta?
    let usage: Usage?
    let error: Failure?

    struct Message: Decodable {
        let id: String
        let model: String
        let usage: Usage
    }

    struct Block: Decodable {
        let type: String
        let id: String?
        let name: String?
        let data: String?
    }

    /// A content delta (with `type`) or a message delta (with `stop_reason`); they share the key.
    struct Delta: Decodable {
        let type: String?
        let text: String?
        let partialJSON: String?
        let thinking: String?
        let signature: String?
        let stopReason: String?

        enum CodingKeys: String, CodingKey {
            case type, text, thinking, signature
            case partialJSON = "partial_json"
            case stopReason = "stop_reason"
        }
    }

    struct Usage: Decodable {
        let inputTokens: Int?
        let outputTokens: Int?
        let cacheReadInputTokens: Int?
        let cacheCreationInputTokens: Int?

        enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
            case outputTokens = "output_tokens"
            case cacheReadInputTokens = "cache_read_input_tokens"
            case cacheCreationInputTokens = "cache_creation_input_tokens"
        }

        var tokens: TokenUsage {
            TokenUsage(
                input: inputTokens, output: outputTokens, cacheRead: cacheReadInputTokens,
                cacheCreation: cacheCreationInputTokens)
        }
    }

    struct Failure: Decodable {
        let type: String
        let message: String
    }

    enum CodingKeys: String, CodingKey {
        case type, index, message, delta, usage, error
        case contentBlock = "content_block"
    }
}

extension WireEvent {
    /// What this event means, nil for a keep-alive.
    fileprivate func modelEvent(named name: String) throws(AnthropicStreamError) -> ModelEvent? {
        switch type {
            case "ping": return nil
            case "message_start":
                guard let message else { throw .malformed(event: name) }
                return .messageStarted(id: message.id, model: message.model, usage: message.usage.tokens)
            case "content_block_start":
                guard let index, let contentBlock else { throw .malformed(event: name) }
                return .blockStarted(index: index, try contentBlock.kind(event: name))
            case "content_block_delta":
                guard let index, let delta else { throw .malformed(event: name) }
                return try delta.contentEvent(index: index, event: name)
            case "content_block_stop":
                guard let index else { throw .malformed(event: name) }
                return .blockStopped(index: index)
            case "message_delta":
                guard let delta else { throw .malformed(event: name) }
                return .messageDelta(
                    stopReason: delta.stopReason.map(StopReason.init(wire:)), usage: usage?.tokens ?? .init())
            case "message_stop": return .messageStopped
            case "error":
                guard let error else { throw .malformed(event: name) }
                throw .provider(ProviderFailure(kind: .init(wire: error.type), message: error.message))
            default: return .unrecognized(event: name, type: type)
        }
    }
}

extension WireEvent.Block {
    fileprivate func kind(event: String) throws(AnthropicStreamError) -> BlockKind {
        switch type {
            case "text": return .text
            case "thinking": return .thinking
            case "redacted_thinking":
                guard let data else { throw .malformed(event: event) }
                return .redactedThinking(data: data)
            case "tool_use":
                guard let id, let name else { throw .malformed(event: event) }
                return .toolUse(id: id, name: name)
            default: return .unrecognized(type: type)
        }
    }
}

extension WireEvent.Delta {
    fileprivate func contentEvent(index: Int, event: String) throws(AnthropicStreamError) -> ModelEvent {
        switch type {
            case "text_delta": return .textDelta(index: index, try require(text, event))
            case "input_json_delta": return .toolInputDelta(index: index, try require(partialJSON, event))
            case "thinking_delta": return .thinkingDelta(index: index, try require(thinking, event))
            case "signature_delta": return .signatureDelta(index: index, try require(signature, event))
            default: return .unrecognized(event: event, type: type ?? "")
        }
    }

    private func require(_ value: String?, _ event: String) throws(AnthropicStreamError) -> String {
        guard let value else { throw .malformed(event: event) }
        return value
    }
}

extension StopReason {
    fileprivate init(wire: String) {
        switch wire {
            case "end_turn": self = .endTurn
            case "max_tokens": self = .maxTokens
            case "stop_sequence": self = .stopSequence
            case "tool_use": self = .toolUse
            case "pause_turn": self = .pauseTurn
            case "refusal": self = .refusal
            case "model_context_window_exceeded": self = .contextWindowExceeded
            default: self = .other(wire)
        }
    }
}

extension ProviderFailure.Kind {
    fileprivate init(wire: String) {
        switch wire {
            case "overloaded_error": self = .overloaded
            case "rate_limit_error": self = .rateLimited
            case "authentication_error": self = .authentication
            case "permission_error": self = .permission
            case "invalid_request_error": self = .invalidRequest
            case "not_found_error": self = .notFound
            case "request_too_large": self = .requestTooLarge
            case "api_error": self = .server
            default: self = .other(wire)
        }
    }
}
