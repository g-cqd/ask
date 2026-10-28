public import Foundation

/// Source-observable Copilot Chat protocol, not a claim of official client or billing parity.
public enum CopilotProtocol {
    public static let name = "copilot-vscode"
    static let clientID = "01ab8ac9400c4e429b23"
    static let userAgent = "GitHubCopilotChat/0.44.0"
    public static let defaultAPI = "https://api.githubcopilot.com"

    public static func endpoint(_ value: String) throws(SignInError) -> URL {
        guard let url = URL(string: value), let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
            parts.scheme == "https", let host = parts.host?.lowercased(),
            host == "githubcopilot.com" || host.hasSuffix(".githubcopilot.com"),
            parts.user == nil, parts.password == nil, parts.port == nil,
            parts.path.isEmpty || parts.path == "/", parts.query == nil, parts.fragment == nil
        else { throw .invalidResponse("Copilot API origin") }
        return URL(string: "https://\(host)")!
    }

    /// The headers of a chat request, as VS Code Copilot Chat 0.44.0 sends them (`chatMLFetcher.ts`, `networking.ts`): the shared
    /// set, `X-GitHub-Api-Version: 2025-05-01`, the intent, the interaction and its type, and the task, which is the request.
    static func chatHeaders(
        _ credential: CopilotCredentials, session: String, interaction: String, userInitiated: Bool
    ) -> [(name: String, value: String)] {
        let request = UUID().uuidString
        var headers = headers(credential, session: session)
            .filter {
                $0.name != "x-github-api-version" && $0.name != "x-request-id"
            }
        headers += [
            ("x-github-api-version", "2025-05-01"), ("x-request-id", request), ("openai-intent", "conversation-agent"),
            ("x-interaction-id", interaction), ("x-interaction-type", "conversation-agent"),
            ("x-agent-task-id", request),
            ("x-initiator", userInitiated ? "user" : "agent")
        ]
        return headers
    }

    static func headers(_ credential: CopilotCredentials, session: String) -> [(name: String, value: String)] {
        [
            ("authorization", "Bearer \(credential.accessToken)"), ("user-agent", userAgent),
            ("editor-version", "vscode/1.115.0"), ("editor-plugin-version", "copilot-chat/0.44.0"),
            ("copilot-integration-id", "vscode-chat"), ("vscode-machineid", credential.machineID),
            ("editor-device-id", credential.deviceID), ("vscode-sessionid", session),
            ("x-github-api-version", "2025-10-01"), ("x-request-id", UUID().uuidString),
            ("accept", "application/json"), ("content-type", "application/json")
        ]
    }
}
