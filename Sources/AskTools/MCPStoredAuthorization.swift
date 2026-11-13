internal import AskAI
internal import AskMCP
internal import Foundation
internal import Synchronization

/// A server's sign-in as the credential file keeps it (roadmap 0067): the header its requests carry, renewed through the stored token
/// endpoint before it runs out, or when the server refuses it. One renewal at a time; requests that find one under way wait for it.
final class MCPStoredAuthorization: MCPAuthorization {
    private let server: String
    private let file: CredentialFile
    private let http: any HTTPTransport
    private let now: @Sendable () -> Date
    private let renewal = Mutex<Task<Bool, Never>?>(nil)

    /// The sign-in to `server` (its canonical address) in `file`, renewed over `http`.
    init(
        server: String,
        file: CredentialFile,
        http: any HTTPTransport,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.server = server
        self.file = file
        self.http = http
        self.now = now
    }

    func header() async -> String? {
        guard var record = (try? file.loadMCP(server: server)) ?? nil else { return nil }
        if Self.tokens(record).isDue(at: now()), await renew() {
            record = ((try? file.loadMCP(server: server)) ?? nil) ?? record
        }
        return "Bearer " + record.accessToken
    }

    func refused(_ challenge: MCPAuthChallenge?) async -> Bool {
        // More scope needs the person: a renewal keeps the scope it had.
        guard challenge?.error != "insufficient_scope" else { return false }
        return await renew()
    }

    /// Renews the stored tokens and saves them; whether new ones are ready. A refused renewal leaves the record for a new sign-in.
    private func renew() async -> Bool {
        let task = renewal.withLock { running -> Task<Bool, Never> in
            if let running { return running }
            let started = Task { await self.renewNow() }
            running = started
            return started
        }
        let renewed = await task.value
        renewal.withLock { if $0 == task { $0 = nil } }
        return renewed
    }

    private func renewNow() async -> Bool {
        guard let record = (try? file.loadMCP(server: server)) ?? nil, !record.refreshToken.isEmpty,
            let endpoint = URL(string: record.tokenEndpoint)
        else { return false }
        guard
            let fresh = try? await MCPOAuthClient.refresh(
                Self.tokens(record),
                tokenEndpoint: endpoint,
                clientID: record.clientID,
                resource: server,
                http: http,
                now: now()
            )
        else { return false }
        var saved = record
        saved.accessToken = fresh.access
        saved.refreshToken = fresh.refresh ?? record.refreshToken
        saved.expiresAt = fresh.expires?.timeIntervalSince1970
        // try?: the caller is told the renewal was not kept, and signs in again
        return (try? file.renewMCP(saved, replacing: record)) == true
    }

    static func tokens(_ record: MCPServerCredentials) -> MCPOAuthTokens {
        MCPOAuthTokens(
            access: record.accessToken,
            refresh: record.refreshToken.isEmpty ? nil : record.refreshToken,
            expires: record.expiresAt.map { Date(timeIntervalSince1970: $0) }
        )
    }
}
