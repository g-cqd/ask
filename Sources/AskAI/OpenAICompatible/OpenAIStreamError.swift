/// Why an OpenAI-compatible event stream could not be decoded.
public enum OpenAIStreamError: Error, Sendable, Equatable {
    /// An event's data was not the JSON this protocol sends.
    case malformed
    /// The stream ended before saying why generation stopped: the response is incomplete.
    case unfinished
    /// The server reported a failure inside the stream.
    case provider(ProviderFailure)
}

extension OpenAIStreamError: StreamDecodingFailure {
    /// A failure the server called transient, or a stream that ended without saying why it stopped, which a
    /// local server does when it is stopped or runs out of memory mid-answer.
    public var isRetryable: Bool {
        switch self {
            case .provider(let failure): failure.isTransient
            case .unfinished: true
            case .malformed: false
        }
    }
}
