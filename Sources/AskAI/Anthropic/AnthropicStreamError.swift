internal import AemiJSON

/// Why an Anthropic stream ended in failure.
public enum AnthropicStreamError: Error, Sendable, Equatable {
    /// The provider sent an `error` event.
    case provider(ProviderFailure)
    /// An event's data was not the shape its name promises.
    case malformed(event: String)
}

extension AnthropicStreamError: StreamDecodingFailure {
    /// An `error` event the provider classified as overloaded, rate limited or a server error.
    public var providerFailure: ProviderFailure? {
        if case .provider(let failure) = self { return failure }
        return nil
    }

    public var isRetryable: Bool {
        if case .provider(let failure) = self { return failure.isTransient }
        return false
    }
}
