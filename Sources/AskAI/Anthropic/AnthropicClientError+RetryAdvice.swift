extension AnthropicClientError: RetryAdvice {
    /// 408, 429 and every 5xx (529 is Anthropic's "overloaded"); stream errors the provider classified as
    /// overloaded, rate limited or a server error; a connection that dropped, mid-stream or before a response.
    public var isRetryable: Bool {
        switch self {
            case .status(let code, let failure, _):
                return code == 408 || code == 429 || (500 ... 599).contains(code)
                    || failure.map(Self.isTransient) == true
            case .stream(.provider(let failure)): return Self.isTransient(failure)
            case .truncated, .transport: return true
            case .stream, .framing: return false
        }
    }

    public var retryAfter: Duration? {
        guard case .status(_, _, let seconds?) = self else { return nil }
        return .milliseconds(Int(seconds * 1_000))
    }

    private static func isTransient(_ failure: ProviderFailure) -> Bool {
        switch failure.kind {
            case .overloaded, .rateLimited, .server: true
            default: false
        }
    }
}
