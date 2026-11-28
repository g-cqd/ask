public import AemiMCP
public import AskAI

/// ask's HTTP transports (`URLSessionTransport`, `PinnedPublicTransport`, a test's stand-in) as AemiMCP's HTTP client, for
/// the Streamable HTTP transport and OAuth discovery and sign-in. Requests and replies pass through unchanged.
public struct MCPHTTPBridge: MCPHTTPClient {
    private let transport: any HTTPTransport

    public init(_ transport: any HTTPTransport) {
        self.transport = transport
    }

    public func send(_ request: MCPHTTPRequest) async throws -> MCPHTTPResponse {
        let reply = try await transport.send(
            HTTPRequest(
                url: request.url,
                method: request.method,
                headers: request.headers,
                body: request.body,
                allowsRedirects: request.allowsRedirects
            )
        )
        return MCPHTTPResponse(status: reply.status, headers: reply.headers, body: reply.body)
    }
}
