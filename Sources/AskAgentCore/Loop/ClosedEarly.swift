internal import AskAI

/// A response stream that ended without the response's end (roadmap 0141): the connection closed between two events, which no layer
/// below saw as an error. Transient, like any lost connection.
struct ClosedEarly: RetryAdvice, CustomStringConvertible {
    var isRetryable: Bool { true }
    var retryAfter: Duration? { nil }
    var description: String { "the connection closed in the middle of the response" }
}
