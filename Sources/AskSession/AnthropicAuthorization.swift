internal import AskAI
internal import Foundation

/// The Anthropic authorization source shared by inference and native model discovery. A named registration ignores
/// ambient credentials; its private file and identity are bound when this owner is constructed.
struct AnthropicAuthorization: Sendable {
    private let file: CredentialFile
    private let connection: ConnectionRecord?
    private let access: ClaudeAccess

    init(file: CredentialFile, connection: ConnectionRecord?, transport: URLSessionTransport) {
        self.file = file
        self.connection = connection
        access = ClaudeAccess(file: file, client: ClaudeAuthClient(transport: transport), connection: connection)
    }

    /// Why a refreshed sign-in could not be saved, while it cannot (ADR-0082); nil otherwise.
    var unsavedReason: String? { access.unsavedReason }

    /// Authorization without refreshing or writing; expired stored access is unavailable to a cache reader.
    func cached(environment: [String: String], now: Double) throws -> AnthropicClient.Auth? {
        if let supplied = try supplied(environment) { return supplied }
        if let key = try storedKey() { return key }
        guard let stored = try file.loadClaude(connection: connection), !stored.needsRefresh(now: now) else {
            return nil
        }
        return .subscription(accessToken: stored.accessToken)
    }

    /// The same precedence, refresh path and sign-out diagnostics inference has always used.
    func auth(environment: [String: String], now: Double) async throws -> AnthropicClient.Auth {
        if let supplied = try supplied(environment) { return supplied }
        if let key = try storedKey() { return key }
        do { return try await access.auth(now: now) } catch ClaudeAccessError.signedOut {
            if let connection { throw ConnectionError.signInRequired(name: connection.name, provider: .anthropic) }
            throw NotSignedIn()
        }
    }

    /// The API key `ask login claude --api-key` stored. Saving one forgets the subscription and signing in to the subscription forgets the
    /// key, so there is never a choice to make between them. A named connection is a subscription only.
    private func storedKey() throws -> AnthropicClient.Auth? {
        guard connection == nil, let stored = try file.loadKey(for: CredentialFile.claudeKeyName) else { return nil }
        return .apiKey(stored.key)
    }

    private func supplied(_ environment: [String: String]) throws -> AnthropicClient.Auth? {
        guard connection == nil else { return nil }
        return try AnthropicEnvironmentAuth.resolve(environment: environment)
    }
}
