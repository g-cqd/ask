internal import AskAI
internal import AskAgentCore
internal import Foundation
internal import Synchronization
internal import Testing

@testable import AskTools

/// `PinnedPublicTransport` (security audit 2026-11-22, CRIT-05): even when `FetchTool`'s preflight resolver returns a public IP and
/// DNS rebinds to `127.0.0.1` or `169.254.169.254` at connection time, the proxy's atomic resolve-and-connect refuses the tunnel with
/// `403` before a single TCP connection reaches the inward address.
@Suite("PinnedPublicTransport defeats TTL=0 DNS rebinding in FetchTool")
struct PinnedPublicTransportTests {
    @Test(.timeLimit(.minutes(1)))
    func `FetchTool blocks TTL=0 DNS rebinding at connect time without dialing the inward address`() async throws {
        let seenTargets = Mutex<[ProxyRequest.Target]>([])
        let proxy = try ProviderProxy(publicInternet: ()) { target, rule in
            seenTargets.withLock { $0.append(target) }
            return ProxyTunnel.connect(
                to: target,
                rule: rule,
                resolvedAddressesForCheckOnly: ["93.184.216.34", "127.0.0.1"]
            )
        }
        defer { proxy.stop() }

        let transport = PinnedPublicTransport(proxy: proxy)
        // Outer preflight sees only a public IP; when URLSession connects through PinnedPublicTransport, DNS has rebound to 127.0.0.1.
        let tool = FetchTool(http: transport) { _ in ["93.184.216.34"] }
        let call = try JSONObject(validating: Array(#"{"url":"https://rebind.example/internal"}"#.utf8))
        let output = await tool.run(call, in: ToolContext(workingDirectory: "/tmp"))
        #expect(output.isError)
        #expect(seenTargets.withLock { $0 } == [.init(host: "rebind.example", port: 443)])
    }

    @Test(.timeLimit(.minutes(1)))
    func `a public resolved address authenticates through the proxy and reaches the dialer`() async throws {
        let dialed = Atomic<Int>(0)
        let proxy = try ProviderProxy(publicInternet: ()) { _, _ in
            _ = dialed.wrappingAdd(1, ordering: .relaxed)
            return .unreachable
        }
        defer { proxy.stop() }

        let transport = PinnedPublicTransport(proxy: proxy)
        let request = HTTPRequest(
            url: URL(string: "https://example.com/")!,
            method: "GET",
            headers: [],
            body: [],
            allowsRedirects: false
        )
        await #expect(throws: HTTPTransportError.self) {
            _ = try await transport.send(request)
        }
        #expect(dialed.load(ordering: .relaxed) >= 1)
    }
}
