internal import AskAI
internal import AskAgentCore
internal import Foundation

/// Adapts Antigravity's Cloud Code backend to the loop, taking the session per request so a long run survives an expiring token.
struct AgyProvider: ModelProvider {
    let access: AgyAccess
    let client: AgyClient
    let versions: AgyVersions

    func stream(_ request: ModelRequest) -> AsyncThrowingStream<ModelEvent, any Error> {
        let (access, client, versions) = (access, client, versions)
        return ModelStream.after {
            let now = Date().timeIntervalSince1970
            let session = try await access.session(now: now)
            return client.stream(request, session: session, version: await versions.current(now: now))
        }
    }
}

/// Access to the stored Antigravity sign-in, which looks in the installed `agy` for a secret Google accepts when the stored one is not.
func makeAgyAccess(transport: URLSessionTransport) -> AgyAccess {
    let file = NamedConnections.file(for: nil)
    return AgyAccess(
        file: file,
        client: AgyAuthClient(transport: transport),
        cloud: AgyCloudClient(transport: transport, versions: AgyVersions.beside(file, transport: transport)),
        findSecret: { try await installedClientSecret(transport: transport) }
    )
}
