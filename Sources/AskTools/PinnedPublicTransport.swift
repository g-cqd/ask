public import AskAI
internal import Foundation
internal import Synchronization

/// A ``URLSessionTransport`` whose HTTPS connections dial through a shared ``ProviderProxy`` in `.publicInternet` mode so DNS
/// resolution and TCP connection are atomic: a hostname that rebinds to an inward address (`127.0.0.1`, `169.254.169.254`, RFC 1918,
/// IPv6 unique-local) is refused before any TCP SYN reaches the inward address (security audit 2026-11-22, CRIT-05).
public struct PinnedPublicTransport: HTTPTransport {
    private static let shared = LazyPinnedSession()
    private let custom: URLSessionTransport?

    public init() { custom = nil }

    init(proxy: ProviderProxy) {
        custom = URLSessionTransport(session: Self.makeSession(for: proxy))
    }

    public func send(_ request: HTTPRequest) async throws -> HTTPStreamingResponse {
        let transport = try custom ?? Self.shared.transport()
        return try await transport.send(request)
    }

    static func makeSession(for proxy: ProviderProxy) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 600
        configuration.connectionProxyDictionary = [
            "HTTPSEnable": 1,
            "HTTPSProxy": "127.0.0.1",
            "HTTPSPort": proxy.port
        ]
        return URLSession(
            configuration: configuration,
            delegate: ProxyAuthDelegate(port: proxy.port, token: proxy.token),
            delegateQueue: nil
        )
    }

    private final class LazyPinnedSession: Sendable {
        private let state = Mutex<(proxy: ProviderProxy, transport: URLSessionTransport)?>(nil)

        func transport() throws -> URLSessionTransport {
            try state.withLock { slot in
                if let slot { return slot.transport }
                let proxy = try ProviderProxy(publicInternet: ())
                let transport = URLSessionTransport(session: PinnedPublicTransport.makeSession(for: proxy))
                slot = (proxy, transport)
                return transport
            }
        }
    }

    private final class ProxyAuthDelegate: NSObject, URLSessionTaskDelegate, Sendable {
        private let port: Int
        private let token: String

        init(port: Int, token: String) {
            self.port = port
            self.token = token
        }

        func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
            didReceive challenge: URLAuthenticationChallenge,
            completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
        ) {
            let space = challenge.protectionSpace
            if space.isProxy(), space.host == "127.0.0.1", space.port == port {
                completionHandler(
                    .useCredential,
                    URLCredential(user: "ask", password: token, persistence: .none)
                )
            } else {
                completionHandler(.performDefaultHandling, nil)
            }
        }
    }
}
