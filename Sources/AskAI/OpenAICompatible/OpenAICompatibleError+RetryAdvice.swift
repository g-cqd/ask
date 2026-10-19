extension OpenAICompatibleError: RetryAdvice {
    /// 408, 429 and every 5xx; a failure the server classified as overloaded, rate limited or a server error; a
    /// connection that dropped, before a response or in the middle of one; and a stream that ended without saying
    /// why it stopped, which a local server does when it is stopped or runs out of memory mid-answer.
    public var isRetryable: Bool {
        switch self {
            case .status(let code, let failure, _):
                return code == 408 || code == 429 || (500 ... 599).contains(code)
                    || failure.map(Self.isTransient) == true
            case .stream(.provider(let failure)): return Self.isTransient(failure)
            case .stream(.unfinished), .truncated, .transport: return true
            case .stream(.malformed), .framing: return false
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
