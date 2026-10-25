/// Antigravity credentials for a request, refreshed and onboarded when they need it.
///
/// An access token lasts about an hour. Google did not rotate the refresh token in the one refresh observed (ADR-0075), so no lock is
/// taken: a save is compare-and-replace, and one that finds the stored record changed leaves it alone, because what the user did last
/// stands. A refresh the server accepted whose save failed is kept in memory and saved on the next call, in case the server did rotate
/// the token and the copy in the file is spent (ADR-0082). When Google refuses the stored application secret, the installed `agy` is
/// searched once for one it accepts.
public struct AgyAccess: Sendable {
    private let unsaved = UnsavedRotation<AgyCredentials>()
    private let file: CredentialFile
    private let client: AgyAuthClient
    private let cloud: AgyCloudClient
    private let findSecret: @Sendable () async throws -> String

    /// Access backed by `file`, refreshing through `client`, onboarding through `cloud`, finding a new secret with `findSecret`.
    public init(
        file: CredentialFile, client: AgyAuthClient, cloud: AgyCloudClient,
        findSecret: @escaping @Sendable () async throws -> String
            // @dl:accept -- Claude's, Codex's and Antigravity's accessors are twins over different credential types and errors; a protocol to share them would cost more than it saves (a refactor of the three, if it is ever worth it, is its own change)
    ) {
        self.file = file
        self.client = client
        self.cloud = cloud
        self.findSecret = findSecret
    }

    /// Whether the server has rotated the refresh token and the file does not hold the new one yet.
    public var rotationIsUnsaved: Bool { unsaved.value != nil }

    /// Why, while the rotation is unsaved: what the file said when it could not take it. Nil once it is saved.
    public var unsavedReason: String? { unsaved.value?.reason }

    /// A session good for a request made at `now`.
    /// - Parameter now: the time, in seconds since 1970.
    /// - Returns: a current access token and the account's project.
    /// - Throws: an ``AgyAccessError``.
    public func session(now: Double) async throws(AgyAccessError) -> AgySession {
        settleUnsaved()
        guard var current = try held() else { throw .signedOut }
        if now >= current.expiresAt { current = try await refreshed(current, now: now) }
        if current.projectID == nil { current = try await onboarded(current) }
        guard let project = current.projectID else { throw .signedOut }
        return AgySession(accessToken: current.accessToken, projectID: project)
    }

    // MARK: - Refresh

    private func refreshed(_ stored: AgyCredentials, now: Double) async throws(AgyAccessError) -> AgyCredentials {
        let secret: String
        if let kept = stored.clientSecret { secret = kept } else { secret = try await find() }
        var fresh: AgyCredentials
        do { fresh = try await exchange(stored, secret: secret, now: now) } catch {
            // A secret that was stored may have been replaced upstream; one found a moment ago has not.
            guard stored.clientSecret != nil, case .refreshFailed(.tokenEndpoint(_, let code)) = error,
                code == "invalid_client"
            else { throw error }
            fresh = try await exchange(stored, secret: try await find(), now: now)
        }
        let onFile = unsaved.value?.stored ?? stored
        let kept: Bool
        do { kept = try file.saveAgy(fresh, ifStill: onFile) } catch {
            unsaved.hold(fresh, replacing: onFile, because: "\(error)")
            return fresh
        }
        // A rotation held from before is cleared by the next call, which finds the file no longer holds what it replaced.
        if kept { return fresh }
        guard let latest = try load() else { throw .signedOut }
        guard now < latest.expiresAt else { throw .changedDuringRefresh }
        return latest
    }

    private func exchange(_ stored: AgyCredentials, secret: String, now: Double) async throws(AgyAccessError)
        -> AgyCredentials
    {
        do { return try await client.refresh(stored, secret: secret, now: now) } catch let error as AgyAuthError {
            throw .refreshFailed(error)
        } catch { throw .unreachable(String(describing: error)) }
    }

    private func find() async throws(AgyAccessError) -> String {
        do { return try await findSecret() } catch { throw .secretUnavailable(String(describing: error)) }
    }

    // MARK: - Onboarding

    /// `credentials` with the account's project, saved when the file can take it.
    private func onboarded(_ credentials: AgyCredentials) async throws(AgyAccessError) -> AgyCredentials {
        let account: AgyAccount
        do { account = try await cloud.account(accessToken: credentials.accessToken) } catch let error as AgyCloudError
        {
            throw .onboarding(error)
        } catch { throw .unreachable(String(describing: error)) }
        var result = credentials
        result.projectID = account.projectID
        result.tierID = account.currentTierID
        if let held = unsaved.value {
            unsaved.hold(result, replacing: held.stored, because: held.reason)
        } else {
            // The project is the account's and is found again if it is not kept, so a failed save costs one request.
            _ = try? file.saveAgy(result, ifStill: credentials)
            // @dl:accept -- Claude's, Codex's and Antigravity's accessors are twins over different credential types and errors; a protocol to share them would cost more than it saves (a refactor of the three, if it is ever worth it, is its own change)
        }
        return result
    }

    // MARK: - Storage

    /// What to use now: the rotated credentials not yet saved, or else what is stored.
    private func held() throws(AgyAccessError) -> AgyCredentials? {
        if let held = unsaved.value { return held.current }
        return try load()
    }

    /// Tries to save credentials that could not be saved before. If what is stored is no longer what they replaced, the user signed
    /// out or in again meanwhile, and what they did stands.
    private func settleUnsaved() {
        guard let held = unsaved.value else { return }
        if (try? file.saveAgy(held.current, ifStill: held.stored)) != nil { unsaved.clear() }
    }

    private func load() throws(AgyAccessError) -> AgyCredentials? {
        do { return try file.loadAgy() } catch { throw .storage(error) }
    }
}
