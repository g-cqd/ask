public import Foundation

/// Streams responses from Cloud Code for an Antigravity account.
///
/// Everything but the protocol is shared with the other clients (``ProviderStream``): framing, error statuses, retry advice and
/// delivery. ``AgyRequestEncoder`` and ``AgyStreamDecoder`` are the only parts that know this protocol, and the identity sent is
/// ask's own (ADR-0080).
public struct AgyClient: Sendable {
    /// Where streaming requests go; the query is part of the address, which is why this is not a path under a base.
    private static let address = URL(
        string: AgyCloud.baseURL.absoluteString + "/v1internal:streamGenerateContent?alt=sse")!
    private let transport: any HTTPTransport
    private let newID: @Sendable () -> String

    /// A client sending through `transport`, naming each request and prompt with `newID`.
    public init(transport: any HTTPTransport, newID: @escaping @Sendable () -> String = { UUID().uuidString }) {
        self.transport = transport
        self.newID = newID
    }

    /// Sends `request` under `session` and streams the response's events. The stream throws a ``ProviderStreamError``, or the
    /// ``ThinkingError`` of a request for an explicit thinking control, before anything is sent.
    public func stream(_ request: ModelRequest, session: AgySession) -> AsyncThrowingStream<ModelEvent, any Error> {
        let body: [UInt8]
        do {
            body = try AgyRequestEncoder.encode(
                request, project: session.projectID, requestID: "ask-" + newID(), promptID: newID())
        } catch { return error.failedStream }
        let endpoint = ProviderEndpoint(
            transport: transport, url: Self.address, apiKey: session.accessToken,
            headers: ["user-agent": AgyCloud.userAgent])
        return endpoint.stream(body, decoder: AgyStreamDecoder.self)
    }
}
