/// Codex credentials for a request, refreshed and saved when they expire.
///
/// The refresh token rotates and is single use, so refreshing is one locked step: take the lock every ask process shares,
/// look again at what is stored (another process may have refreshed while this one waited), and only then refresh and
/// save the whole replacement, only if what is stored is still what was refreshed. A failed refresh leaves what was stored
/// as it was and is not retried, because the server may already have spent the token. A refresh the server accepted but whose save
/// failed is kept in memory and saved on the next call, so a transient failure does not sign the user out (ADR-0082).
public struct CodexAccess: Sendable {
    private let unsaved = UnsavedRotation<CodexCredentials>()
    private let file: CredentialFile
    private let client: CodexAuthClient
    private let lockWait: Duration
    private let connection: ConnectionRecord?

    /// Access backed by `file`, refreshing through `client`, waiting up to `lockWait` for another process's refresh.
    public init(
        file: CredentialFile, client: CodexAuthClient, lockWait: Duration = .seconds(30),
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

    /// Credentials good for a request made at `now` (seconds since 1970).
    /// - Parameter now: the time, in seconds since 1970.
    /// - Returns: the stored credentials, or their refreshed replacement.
    /// - Throws: a ``CodexAccessError``.
    public func credentials(now: Double) async throws(CodexAccessError) -> CodexCredentials {
        settleUnsaved()
        guard let stored = try held() else { throw .signedOut }
        guard stored.needsRefresh(now: now) else { return stored }
        let lock = try await take()
        defer { lock.release() }
        guard let current = try held() else { throw .signedOut }
        guard current.needsRefresh(now: now) else { return current }
        let fresh: CodexCredentials
        do { fresh = try await client.refresh(current, now: now) } catch { throw .refreshFailed(error) }
        if connection != nil, fresh.accountID != current.accountID { throw .accountChanged }
        let onFile = unsaved.value?.stored ?? current
        let kept: Bool
        do { kept = try file.saveCodex(fresh, ifStill: onFile, connection: connection) } catch {
            // The server has spent the token in the file; the replacement is the only usable copy, so keep it and go on.
            unsaved.hold(fresh, replacing: onFile, because: "\(error)")
            return fresh
        }
        unsaved.clear()
        if kept { return fresh }
        // The user signed out, or in again, while the response was on its way: what they did last stands.
        guard let latest = try load() else { throw .signedOut }
        guard !latest.needsRefresh(now: now) else { throw .changedDuringRefresh }
        return latest
    }

    /// What to use now: the rotated credentials not yet saved, or else what is stored.
    private func held() throws(CodexAccessError) -> CodexCredentials? {
        if let held = unsaved.value { return held.current }
        return try load()
    }

    /// Tries to save rotated credentials that could not be saved before. If what is stored is no longer what they replaced, the user
    /// signed out or in again meanwhile, and what they did stands.
    private func settleUnsaved() {
        guard let held = unsaved.value else { return }
        if (try? file.saveCodex(held.current, ifStill: held.stored, connection: connection)) != nil { unsaved.clear() }
    }

    private func load() throws(CodexAccessError) -> CodexCredentials? {
        do { return try file.loadCodex(connection: connection) } catch { throw .storage(error) }
    }

    private func take() async throws(CodexAccessError) -> CredentialLock {
        do { return try await CredentialLock.acquire(beside: file.url, wait: lockWait) } catch {
            switch error {
                case .timedOut, .cancelled: throw .lockUnavailable
                case .io(let failure): throw .storage(failure)
            }
        }
    }
}
