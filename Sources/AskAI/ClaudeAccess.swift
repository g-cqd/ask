/// Why no request auth could be produced.
public enum ClaudeAccessError: Error, Sendable, Equatable {
    /// Nothing is stored: `ask login` first.
    case signedOut
    /// The stored credentials could not be read.
    case storage(CredentialFileError)
    /// The credentials expired and could not be refreshed. `invalid_grant` means signing in again.
    case refreshFailed(ClaudeAuthError)
}

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
        guard credentials.needsRefresh(now: now) else { return .subscription(accessToken: credentials.accessToken) }
        let refreshed: ClaudeCredentials
        do { refreshed = try await client.refresh(credentials, now: now) } catch { throw .refreshFailed(error) }
        do { try file.saveClaude(refreshed) } catch { throw .storage(error) }
        return .subscription(accessToken: refreshed.accessToken)
    }
}
