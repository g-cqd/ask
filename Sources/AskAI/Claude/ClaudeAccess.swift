/// Request auth from stored Claude credentials, refreshing and saving them when they expire.
///
/// The refresh token rotates and is single use (probed live, ADR-0074): the spent token is refused with `invalid_grant`, and of
/// two refreshes of one token sent together exactly one succeeds. So refreshing is one locked step, as Codex's is: take the lock
/// every ask process shares, look again at what is stored (another process may have refreshed while this one waited), and only
/// then refresh and save the whole replacement, only if what is stored is still what was refreshed. A failed refresh leaves what
/// was stored as it was and is not retried, because the server may already have spent the token. A refresh the server accepted but
/// whose save failed is kept in memory and saved on the next call, so a transient failure does not sign the user out (ADR-0082).
public struct ClaudeAccess: Sendable {
    private let unsaved = UnsavedRotation<ClaudeCredentials>()
    private let file: CredentialFile
    private let client: ClaudeAuthClient
    private let connection: ConnectionRecord?
    private let lockWait: Duration

    /// The refresh lock's name: Claude's own, so a Codex refresh in the same file does not hold it up.
    static let lockName = "claude-refresh"

    /// Access backed by `file`, refreshing through `client`, waiting up to `lockWait` for another process's refresh.
    public init(
        // @dl:accept -- Claude's and Codex's accessors are twins over different credential types and errors; a protocol to share them would cost more than it saves
        file: CredentialFile, client: ClaudeAuthClient, lockWait: Duration = .seconds(30),
        connection: ConnectionRecord? = nil
    ) {
        self.file = file
        self.client = client
        self.lockWait = lockWait
        self.connection = connection
    }

    /// Whether the server has rotated the token and the file does not hold the new one yet.
    public var rotationIsUnsaved: Bool { unsaved.value != nil }

    /// Why, while the rotation is unsaved: what the file said when it could not take the new pair. Nil once it is saved.
    public var unsavedReason: String? { unsaved.value?.reason }

    /// Auth for a request made at `now` (seconds since 1970).
    /// - Throws: a ``ClaudeAccessError``. A failed refresh leaves the stored credentials as they were.
    public func auth(now: Double) async throws(ClaudeAccessError) -> AnthropicClient.Auth {
        settleUnsaved()
        guard let stored = try current() else { throw .signedOut }
        guard stored.needsRefresh(now: now) else { return .subscription(accessToken: stored.accessToken) }
        let lock = try await take()
        defer { lock.release() }
        guard let credentials = try current() else { throw .signedOut }
        guard credentials.needsRefresh(now: now) else { return .subscription(accessToken: credentials.accessToken) }
        let refreshed: ClaudeCredentials
        do { refreshed = try await client.refresh(credentials, now: now) } catch { throw .refreshFailed(error) }
        // The refresh names the account, and a named connection must not quietly move to another one.
        // @dl:accept -- Claude's and Codex's accessors are twins over different credential types and errors; a protocol to share them would cost more than it saves
        if connection != nil, let before = credentials.accountEmail, refreshed.accountEmail != before {
            throw .accountChanged
        }
        let onFile = unsaved.value?.stored ?? credentials
        let kept: Bool
        do { kept = try file.saveClaude(refreshed, ifStill: onFile, connection: connection) } catch {
            // The server has spent the token in the file; the replacement is the only usable copy, so keep it and go on.
            unsaved.hold(refreshed, replacing: onFile, because: "\(error)")
            return .subscription(accessToken: refreshed.accessToken)
        }
        unsaved.clear()
        if kept { return .subscription(accessToken: refreshed.accessToken) }
        // The user signed out, or in again, while the response was on its way: what they did last stands.
        guard let latest = try load() else { throw .signedOut }
        guard !latest.needsRefresh(now: now) else { throw .changedDuringRefresh }
        return .subscription(accessToken: latest.accessToken)
        // @dl:accept -- Claude's and Codex's accessors are twins over different credential types and errors; a protocol to share them would cost more than it saves
    }

    /// What to use now: the rotated credentials not yet saved, or else what is stored.
    private func current() throws(ClaudeAccessError) -> ClaudeCredentials? {
        // @dl:accept -- Claude's, Codex's and Antigravity's accessors are twins over different credential types and errors; a protocol to share them would cost more than it saves
        if let held = unsaved.value { return held.current }
        return try load()
    }

    /// Tries to save rotated credentials that could not be saved before. If what is stored is no longer what they replaced, the user
    /// signed out or in again meanwhile, and what they did stands.
    private func settleUnsaved() {
        guard let held = unsaved.value else { return }
        if (try? file.saveClaude(held.current, ifStill: held.stored, connection: connection)) != nil { unsaved.clear() }
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
