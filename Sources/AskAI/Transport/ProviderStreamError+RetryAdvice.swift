extension ProviderStreamError: RetryAdvice {
    /// 408, 429 and every 5xx, or a reason the provider calls transient; a stream failure the decoder calls
    /// retryable; and a connection that dropped, before a response or in the middle of one.
    public var isRetryable: Bool {
        switch self {
            case .status(let code, let failure, _): ProviderFailure.isRetryable(status: code, failure: failure)
            case .stream(let failure): failure.isRetryable
            case .truncated, .transport: true
            case .framing: false
        }
    }

    public var isContextOverflow: Bool {
        switch self {
            case .status(_, let failure?, _): failure.kind == .contextOverflow
            case .stream(let failure): failure.providerFailure?.kind == .contextOverflow
            default: false
        }
    }

    public var reportedContextWindow: Int? {
        switch self {
            case .status(_, let failure?, _): failure.contextWindow
            case .stream(let failure): failure.providerFailure?.contextWindow
            default: nil
        }
    }

    public var retryAfter: Duration? {
        guard case .status(_, _, let seconds?) = self else { return nil }
        return .milliseconds(Int(seconds * 1_000))
    }
}
