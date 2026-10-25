internal import Foundation

@testable import AskAI

/// What the Antigravity access tests share: a credential file, stored records, and the server's replies.
struct AgyAccessWorld {
    let file = CredentialFile(
        url: FileManager.default.temporaryDirectory.appending(
            path: "ask-agy-access-\(UUID().uuidString)/ask/credentials.json"),
        lockWait: .milliseconds(50))
    static let refreshed = #"{"access_token":"at-2","expires_in":3599,"token_type":"Bearer","scope":"s"}"#
    static let rotated = #"{"access_token":"at-2","refresh_token":"rt-2","expires_in":3599,"token_type":"Bearer"}"#
    static let onboarding =
        #"{"cloudaicompanionProject":"proj-1","currentTier":{"id":"free-tier"},"paidTier":{"id":"g1-pro-tier"}}"#
    let expired = AgyCredentials(
        accessToken: "at-1", refreshToken: "rt-1", expiresAt: 100, projectID: "proj-0", tierID: "t",
        clientSecret: "secret-1")
    let valid = AgyCredentials(
        accessToken: "at-ok", refreshToken: "rt-1", expiresAt: 10_000, projectID: "proj-0", tierID: "t",
        clientSecret: "secret-1")

    /// Access that sends everything through `transport`, and finds a secret by `secret` when it has to.
    func access(_ transport: any HTTPTransport, secret: @escaping @Sendable () async throws -> String = { "found" })
        -> AgyAccess
    {
        AgyAccess(
            file: file, client: AgyAuthClient(transport: transport), cloud: AgyCloudClient(transport: transport),
            findSecret: secret)
    }

    func body(_ request: HTTPRequest) -> String { String(decoding: request.body, as: UTF8.self) }
}
