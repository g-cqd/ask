/// Why a request to an OpenAI-compatible server failed. Each case calls for a different response.
public enum OpenAICompatibleError: Error, Sendable, Equatable {
    /// The server answered with a non-2xx status, its reason when the body carried one, and the seconds its
    /// `retry-after` header asked for, when it sent one.
    case status(Int, ProviderFailure?, retryAfter: Double? = nil)
    /// The event stream reported a failure, or broke the protocol.
    case stream(OpenAIStreamError)
    /// The event stream exceeded a size limit.
    case framing(SSEError)
    /// The connection closed in the middle of an event.
    case truncated
    /// The request did not complete.
    case transport(String)
}
