/// Why an OpenAI-compatible event stream could not be decoded.
public enum OpenAIStreamError: Error, Sendable, Equatable {
    /// An event's data was not the JSON this protocol sends.
    case malformed
    /// The stream ended before saying why generation stopped: the response is incomplete.
    case unfinished
    /// The server reported a failure inside the stream.
    case provider(ProviderFailure)
}
