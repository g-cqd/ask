/// Why an event stream was refused.
public enum SSEError: Error, Sendable, Equatable {
    /// One event, or one line, exceeded ``SSEDecoder/Limits/maximumEventBytes``.
    case eventTooLarge(limit: Int)
}
