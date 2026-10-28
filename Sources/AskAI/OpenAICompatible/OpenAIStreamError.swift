/// Why an OpenAI-compatible event stream could not be decoded.
public enum OpenAIStreamError: Error, Sendable, Equatable {
    /// An event's data was not the JSON this protocol sends; `event` is the frame's head, so a server's
    /// undocumented shape names the bytes that broke the decode instead of dying namelessly (diary 22 fixed
    /// one such shape only because the session's bytes were found by hand).
    case malformed(event: String)
    /// The stream ended before saying why generation stopped: the response is incomplete.
    case unfinished
    /// The server reported a failure inside the stream.
    case provider(ProviderFailure)

    /// The refusal for a frame that did not decode, carrying its head as evidence.
    public static func malformed(of data: [UInt8]) -> OpenAIStreamError {
        .malformed(event: head(of: data))
    }

    /// The first bytes of a frame, at most 240 of them, cut at a UTF-8 boundary and saying how large it was.
    static func head(of data: [UInt8]) -> String {
        guard data.count > 240 else { return String(decoding: data, as: UTF8.self) }
        var cut = Array(data.prefix(240))
        while let last = cut.last, last & 0xC0 == 0x80 { cut.removeLast() }
        return String(decoding: cut, as: UTF8.self) + "… \(data.count) bytes in all"
    }
}

extension OpenAIStreamError: StreamDecodingFailure {
    /// A failure the server called transient, or a stream that ended without saying why it stopped, which a
    /// local server does when it is stopped or runs out of memory mid-answer.
    public var providerFailure: ProviderFailure? {
        if case .provider(let failure) = self { return failure }
        return nil
    }

    public var isRetryable: Bool {
        switch self {
            case .provider(let failure): failure.isTransient
            case .unfinished: true
            case .malformed: false
        }
    }
}

extension OpenAIStreamError: CustomStringConvertible {
    /// A sentence for the person reading it, with the bytes that broke the decode where the answer is.
    public var description: String {
        switch self {
            case .malformed(let event): "an event that is not this protocol's JSON: \(event)"
            case .unfinished: "the stream ended without saying why it stopped"
            case .provider(let failure): failure.sentence
        }
    }
}
