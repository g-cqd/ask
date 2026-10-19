/// What a provider's error says about trying again, without the caller knowing the provider's protocol.
///
/// The loop asks this of any error a provider stream throws. A provider adopts it for its own error type, in
/// its own directory, so the loop stays provider-neutral.
public protocol RetryAdvice: Error {
    /// Whether the same request may succeed if sent again: overload, rate limits, server errors, a dropped
    /// connection. A malformed request or a refused credential never does.
    var isRetryable: Bool { get }
    /// How long the provider asked the caller to wait, when it said.
    var retryAfter: Duration? { get }
    /// Whether the request was refused for being longer than the model's context window, which compacting the
    /// conversation can cure. A requirement, not only an extension, so it dispatches through `any RetryAdvice`.
    var isContextOverflow: Bool { get }
    /// The context window a refusal for length named, so the caller can size later requests to it.
    var reportedContextWindow: Int? { get }
}

extension RetryAdvice {
    public var isContextOverflow: Bool { false }
    public var reportedContextWindow: Int? { nil }
}
