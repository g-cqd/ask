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
}

extension ModelEventDecoding {
    public mutating func finish(into events: inout [ModelEvent]) throws(Failure) {}
}
