/// Request auth from stored Claude credentials, refreshing and saving them when they expire.
///
/// The refresh token rotates and is single use (probed live, ADR-0073): the spent token is refused with `invalid_grant`, and of
/// two refreshes of one token sent together exactly one succeeds. So refreshing is one locked step, as Codex's is: take the lock
/// every ask process shares, look again at what is stored (another process may have refreshed while this one waited), and only
/// then refresh and save the whole replacement, only if what is stored is still what was refreshed. A failed refresh leaves what
/// was stored as it was and is not retried, because the server may already have spent the token.
public struct ClaudeAccess: Sendable {
    private let file: CredentialFile
    private let client: ClaudeAuthClient
    private let connection: ConnectionRecord?
    private let lockWait: Duration

    /// The refresh lock's name: Claude's own, so a Codex refresh in the same file does not hold it up.
    static let lockName = "claude-refresh"

    /// Access backed by `file`, refreshing through `client`, waiting up to `lockWait` for another process's refresh.
    // @dl:accept -- Claude's and Codex's accessors are twins over different credential types and errors; a protocol to share them would cost more than it saves
    public init(
        file: CredentialFile, client: ClaudeAuthClient, lockWait: Duration = .seconds(30),
        connection: ConnectionRecord? = nil
    ) {
        self.file = file
        self.client = client
        self.lockWait = lockWait
        self.connection = connection
    }

    /// Auth for a request made at `now` (seconds since 1970).
    /// - Throws: a ``ClaudeAccessError``. A failed refresh leaves the stored credentials as they were.
    public func auth(now: Double) async throws(ClaudeAccessError) -> AnthropicClient.Auth {
        guard let stored = try load() else { throw .signedOut }
        guard stored.needsRefresh(now: now) else { return .subscription(accessToken: stored.accessToken) }
        let lock = try await take()
        defer { lock.release() }
        guard let credentials = try load() else { throw .signedOut }
        guard credentials.needsRefresh(now: now) else { return .subscription(accessToken: credentials.accessToken) }
        let refreshed: ClaudeCredentials
        do { refreshed = try await client.refresh(credentials, now: now) } catch { throw .refreshFailed(error) }
        // The refresh names the account, and a named connection must not quietly move to another one.
        if connection != nil, let before = credentials.accountEmail, refreshed.accountEmail != before {
            throw .accountChanged
        }
        let kept: Bool
        do { kept = try file.saveClaude(refreshed, ifStill: credentials, connection: connection) } catch {
            throw .storage(error)
        }
        if kept { return .subscription(accessToken: refreshed.accessToken) }
        // The user signed out, or in again, while the response was on its way: what they did last stands.
        guard let latest = try load() else { throw .signedOut }
        guard !latest.needsRefresh(now: now) else { throw .changedDuringRefresh }
        return .subscription(accessToken: latest.accessToken)
        // @dl:accept -- Claude's and Codex's accessors are twins over different credential types and errors; a protocol to share them would cost more than it saves
    }

    private func load() throws(ClaudeAccessError) -> ClaudeCredentials? {
        do { return try file.loadClaude(connection: connection) } catch { throw .storage(error) }
    }

    private func take() async throws(ClaudeAccessError) -> CredentialLock {
        do { return try await CredentialLock.acquire(beside: file.url, wait: lockWait, name: Self.lockName) } catch {
            switch error {
                case .timedOut, .cancelled: throw .lockUnavailable
                case .io(let failure): throw .storage(failure)
            }
        }
    }
}
