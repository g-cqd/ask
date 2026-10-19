public import Foundation

/// Where a provider's streaming requests go, and how they are authenticated: the part of a client that is the same
/// whatever the protocol. A client supplies the body its protocol encodes and the decoder that reads the answer.
struct ProviderEndpoint: Sendable {
    private let transport: any HTTPTransport
    private let url: URL
    private let apiKey: String?
    private let headers: [String: String]

    /// The endpoint `path` beneath `baseURL`.
    /// - Parameters:
    ///   - transport: what sends the requests.
    ///   - baseURL: the API root.
    ///   - path: the protocol's path beneath it.
    ///   - apiKey: sent as a bearer token when there is one.
    ///   - headers: extra headers the server asks for.
    init(transport: any HTTPTransport, baseURL: URL, path: String, apiKey: String?, headers: [String: String]) {
        self.transport = transport
        self.url = baseURL.appending(path: path)
        self.apiKey = apiKey
        self.headers = headers
    }

    /// Sends `body` as a server-sent-events request and streams what `decoder` makes of the answer.
    /// - Parameters:
    ///   - body: the encoded request.
    ///   - decoder: the protocol's decoder.
    /// - Returns: the events; the stream throws a ``ProviderStreamError``.
    func stream<Decoder: ModelEventDecoding>(_ body: [UInt8], decoder: Decoder.Type)
        -> AsyncThrowingStream<ModelEvent, any Error>
    {
        var fields: [(name: String, value: String)] = [
            ("content-type", "application/json"), ("accept", "text/event-stream"), ("user-agent", "ask")
        ]
        if let apiKey, !apiKey.isEmpty { fields.append(("authorization", "Bearer \(apiKey)")) }
        fields += headers.sorted { $0.key < $1.key }.map { (name: $0.key, value: $0.value) }
        let http = HTTPRequest(url: url, method: "POST", headers: fields, body: body)
        return ProviderStream.events(http, over: transport, decoder: decoder, succeeds: { (200 ... 299).contains($0) })
    }
}
