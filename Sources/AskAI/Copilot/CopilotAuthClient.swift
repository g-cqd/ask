internal import Foundation

/// Exchanges the retained GitHub grant; refresh timing uses local time plus refresh_in, not the server's clock.
public struct CopilotAuthClient: Sendable {
    let http: CopilotHTTP
    public init(transport: any HTTPTransport) { http = CopilotHTTP(transport: transport) }

    public func exchange(
        githubToken: String, machineID: String, deviceID: String, now: Double
    ) async throws(SignInError) -> CopilotCredentials {
        guard SignInSecret.isValid(githubToken), now.isFinite else { throw .invalidResponse("GitHub grant") }
        let envelope = try await http.json(
            HTTPRequest(
                url: URL(string: "https://api.github.com/copilot_internal/v2/token")!, method: "GET",
                headers: [
                    ("authorization", "token \(githubToken)"), ("accept", "application/json"),
                    ("user-agent", CopilotProtocol.userAgent), ("x-github-api-version", "2025-04-01")
                ],
                body: [], allowsRedirects: false), as: Envelope.self)
        guard SignInSecret.isValid(envelope.token), envelope.expires_at > 0,
            (1 ... 86_400).contains(envelope.refresh_in), (now + Double(envelope.refresh_in)).isFinite
        else { throw .invalidResponse("Copilot token envelope") }
        let api = try CopilotProtocol.endpoint(envelope.endpoints?.api ?? CopilotProtocol.defaultAPI)
        return try CopilotCredentials(
            githubToken: githubToken, accessToken: envelope.token, expiresAt: now + Double(envelope.refresh_in),
            apiURL: api.absoluteString, machineID: machineID, deviceID: deviceID
        )
        .validated()
    }

    private struct Envelope: Decodable {
        struct Endpoints: Decodable { let api: String? }
        let token: String
        let expires_at: Int
        let refresh_in: Int
        let endpoints: Endpoints?
    }
}
