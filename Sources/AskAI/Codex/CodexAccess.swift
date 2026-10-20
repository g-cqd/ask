/// Codex credentials for a request, refreshed and saved when they expire.
///
/// The refresh token rotates and is single use, so refreshing is one locked step: take the lock every ask process shares,
/// look again at what is stored (another process may have refreshed while this one waited), and only then refresh and
/// save the whole replacement, only if what is stored is still what was refreshed. A failed refresh leaves what was stored
/// as it was and is not retried, because the server may already have spent the token.
public struct CodexAccess: Sendable {
    private let file: CredentialFile
    private let client: CodexAuthClient
    private let lockWait: Duration

    /// Access backed by `file`, refreshing through `client`, waiting up to `lockWait` for another process's refresh.
    public init(file: CredentialFile, client: CodexAuthClient, lockWait: Duration = .seconds(30)) {
        self.file = file
        self.client = client
        self.lockWait = lockWait
    }

    /// Credentials good for a request made at `now` (seconds since 1970).
    /// - Parameter now: the time, in seconds since 1970.
    /// - Returns: the stored credentials, or their refreshed replacement.
    /// - Throws: a ``CodexAccessError``.
    public func credentials(now: Double) async throws(CodexAccessError) -> CodexCredentials {
        guard let stored = try load() else { throw .signedOut }
        guard stored.needsRefresh(now: now) else { return stored }
        let lock = try await take()
        defer { lock.release() }
        guard let current = try load() else { throw .signedOut }
        guard current.needsRefresh(now: now) else { return current }
        let fresh: CodexCredentials
        do { fresh = try await client.refresh(current, now: now) } catch { throw .refreshFailed(error) }
        let kept: Bool
        do { kept = try file.saveCodex(fresh, ifStill: current) } catch { throw .storage(error) }
        if kept { return fresh }
        // The user signed out, or in again, while the response was on its way: what they did last stands.
        guard let latest = try load() else { throw .signedOut }
        guard !latest.needsRefresh(now: now) else { throw .changedDuringRefresh }
        return latest
    }

    private func load() throws(CodexAccessError) -> CodexCredentials? {
        do { return try file.loadCodex() } catch { throw .storage(error) }
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
