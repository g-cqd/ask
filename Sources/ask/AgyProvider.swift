internal import AskAI
internal import AskAgentCore
internal import Foundation

/// Adapts Antigravity's Cloud Code backend to the loop, taking the session per request so a long run survives an expiring token.
struct AgyProvider: ModelProvider {
    let access: AgyAccess
    let client: AgyClient

    func stream(_ request: ModelRequest) -> AsyncThrowingStream<ModelEvent, any Error> {
        let (access, client) = (access, client)
        return ModelStream.after {
            let session = try await access.session(now: Date().timeIntervalSince1970)
            return client.stream(request, session: session)
        }
    }
}

/// Access to the stored Antigravity sign-in, which looks in the installed `agy` for a secret Google accepts when the stored one is not.
func makeAgyAccess(transport: URLSessionTransport) -> AgyAccess {
    AgyAccess(
        file: NamedConnections.file(for: nil), client: AgyAuthClient(transport: transport),
        cloud: AgyCloudClient(transport: transport),
        findSecret: { try await installedClientSecret(transport: transport) })
}
