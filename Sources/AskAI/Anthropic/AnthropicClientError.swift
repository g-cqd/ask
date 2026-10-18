internal import AemiJSON
internal import Foundation

/// Why an Anthropic request failed. Each case calls for a different response.
public enum AnthropicClientError: Error, Sendable, Equatable {
    /// The API answered with a non-2xx status, and its reason when the body carried one.
    case status(Int, ProviderFailure?)
    /// The event stream reported a failure, or broke the protocol.
    case stream(AnthropicStreamError)
    /// The event stream exceeded a size limit.
    case framing(SSEError)
    /// The connection closed in the middle of an event.
    case truncated
    /// The request did not complete.
    case transport(String)
}
