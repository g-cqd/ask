/// Decodes a provider's server-sent events into neutral ``ModelEvent``s, one event at a time.
///
/// A provider's decoder is the only part of its stream handling that knows its protocol: framing, error statuses,
/// truncation, retry advice and delivery are shared (``ProviderStream``).
public protocol ModelEventDecoding: Sendable {
    /// Why an event could not be decoded.
    associatedtype Failure: StreamDecodingFailure

    /// A decoder at the start of a response.
    init()

    /// Decodes one event, appending what it means to `events`.
    mutating func decode(_ frame: SSEEvent, into events: inout [ModelEvent]) throws(Failure)

    /// Appends what the end of the stream means, such as closing blocks the protocol leaves open.
    mutating func finish(into events: inout [ModelEvent]) throws(Failure)

    /// The provider's reason in the body of a non-2xx response, if the body gives one.
    static func failure(inErrorBody body: [UInt8]) -> ProviderFailure?

    /// The provider's refusal, including any quota evidence in the HTTP response headers.
    static func failure(inErrorBody body: [UInt8], status: Int, headers: [String: String]) -> ProviderFailure?
}

extension ModelEventDecoding {
    /// Defaults to the body-only interpretation for protocols with no header-specific failures.
    public static func failure(inErrorBody body: [UInt8], status: Int, headers: [String: String]) -> ProviderFailure? {
        failure(inErrorBody: body)
    }

    public mutating func finish(into events: inout [ModelEvent]) throws(Failure) {}
}
