public import AskAI
internal import Synchronization

/// A ``URLSessionTransport`` whose HTTPS connections dial through a shared ``ProviderProxy`` in `.publicInternet` mode so DNS
/// resolution and TCP connection are atomic: a hostname that rebinds to an inward address (`127.0.0.1`, `169.254.169.254`, RFC 1918,
/// IPv6 unique-local) is refused before any TCP SYN reaches the inward address (security audit 2026-11-22, CRIT-05).
public struct PinnedPublicTransport: HTTPTransport {
    private static let shared = LazyPinnedSession()
    private let custom: URLSessionTransport?

    public init() { custom = nil }

    init(proxy: ProviderProxy) {
        custom = URLSessionTransport(loopbackHTTPSProxyPort: proxy.port, proxyToken: proxy.token)
    }

    public func send(_ request: HTTPRequest) async throws -> HTTPStreamingResponse {
        let transport = try custom ?? Self.shared.transport()
        return try await transport.send(request)
    }

    private final class LazyPinnedSession: Sendable {
        private let state = Mutex<(proxy: ProviderProxy, transport: URLSessionTransport)?>(nil)

        func transport() throws -> URLSessionTransport {
            try state.withLock { slot in
                if let slot { return slot.transport }
                let proxy = try ProviderProxy(publicInternet: ())
                let transport = URLSessionTransport(loopbackHTTPSProxyPort: proxy.port, proxyToken: proxy.token)
                slot = (proxy, transport)
                return transport
            }
        }
    }
}
