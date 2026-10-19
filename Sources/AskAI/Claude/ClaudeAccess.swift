/// Request auth from stored Claude credentials, refreshing and saving them when they expire.
public struct ClaudeAccess: Sendable {
    private let file: CredentialFile
    private let client: ClaudeAuthClient

    /// Access backed by `file`, refreshing through `client`.
    public init(file: CredentialFile, client: ClaudeAuthClient) {
        self.file = file
        self.client = client
    }

    /// Auth for a request made at `now` (seconds since 1970).
    /// - Throws: a ``ClaudeAccessError``. A failed refresh leaves the stored credentials as they were.
    public func auth(now: Double) async throws(ClaudeAccessError) -> AnthropicClient.Auth {
        let stored: ClaudeCredentials?
        do { stored = try file.loadClaude() } catch { throw .storage(error) }
        guard let credentials = stored else { throw .signedOut }
        // @dl:accept -- load, refresh, save is every subscription's access; Codex's adds a lock around it and has its own errors
        guard credentials.needsRefresh(now: now) else { return .subscription(accessToken: credentials.accessToken) }
        let refreshed: ClaudeCredentials
        do { refreshed = try await client.refresh(credentials, now: now) } catch { throw .refreshFailed(error) }
        do { try file.saveClaude(refreshed) } catch { throw .storage(error) }
        return .subscription(accessToken: refreshed.accessToken)
    }
}
