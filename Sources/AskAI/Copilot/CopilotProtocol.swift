public import Foundation

/// Source-observable Copilot Chat protocol, not a claim of official client or billing parity.
public enum CopilotProtocol {
    public static let name = "copilot-vscode"
    static let clientID = "01ab8ac9400c4e429b23"
    public static let defaultAPI = "https://api.githubcopilot.com"

    public static func endpoint(_ value: String) throws(SignInError) -> URL {
        guard let url = URL(string: value), let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
            parts.scheme == "https", let host = parts.host?.lowercased(),
            host == "githubcopilot.com" || host.hasSuffix(".githubcopilot.com"),
            parts.user == nil, parts.password == nil, parts.port == nil,
            parts.path.isEmpty || parts.path == "/", parts.query == nil, parts.fragment == nil,
            let origin = URL(string: "https://\(host)")
        else { throw .invalidResponse("Copilot API origin") }
        return origin
    }

    /// The headers of a chat request, as VS Code's built-in Copilot Chat 0.72.0 sends them over HTTP (`chatMLFetcher.ts`, `networkRequest`
    /// in `networking.ts`): the shared set, `X-GitHub-Api-Version: 2026-01-09`, the intent, the interaction and its type, and the task,
    /// which is the request. (`2025-05-01` is now its WebSocket path's.)
    static func chatHeaders(
        _ credential: CopilotCredentials,
        session: String,
        interaction: String,
        userInitiated: Bool,
        version: CopilotClientVersion
    ) -> [(name: String, value: String)] {
        let request = UUID().uuidString
        var headers = headers(credential, session: session, version: version)
            .filter {
                $0.name != "x-github-api-version" && $0.name != "x-request-id"
            }
        headers += [
            ("x-github-api-version", "2026-01-09"), ("x-request-id", request), ("openai-intent", "conversation-agent"),
            ("x-interaction-id", interaction), ("x-interaction-type", "conversation-agent"),
            ("x-agent-task-id", request),
            ("x-initiator", userInitiated ? "user" : "agent")
        ]
        return headers
    }

    static func headers(
        _ credential: CopilotCredentials,
        session: String,
        version: CopilotClientVersion
    ) -> [(name: String, value: String)] {
        [
            ("authorization", "Bearer \(credential.accessToken)"), ("user-agent", version.userAgent),
            ("editor-version", "vscode/\(version.vscode)"), ("editor-plugin-version", "copilot-chat/\(version.chat)"),
            ("copilot-integration-id", "vscode-chat"), ("vscode-machineid", credential.machineID),
            ("editor-device-id", credential.deviceID), ("vscode-sessionid", session),
            ("x-github-api-version", "2025-10-01"), ("x-request-id", UUID().uuidString),
            ("accept", "application/json"), ("content-type", "application/json")
        ]
    }
}
