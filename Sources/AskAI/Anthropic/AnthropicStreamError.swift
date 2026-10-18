internal import AemiJSON

/// Why an Anthropic stream ended in failure.
public enum AnthropicStreamError: Error, Sendable, Equatable {
    /// The provider sent an `error` event.
    case provider(ProviderFailure)
    /// An event's data was not the shape its name promises.
    case malformed(event: String)
}
