package import Foundation

/// Verifies `Cf-Access-Jwt-Assertion` on every controller HTTP and WebSocket request (ADR-0170), caching the team's JSON Web Key Set
/// and refreshing it (at most once every 30 seconds) when an unknown key id arrives.
package actor AccessVerifier {
    package enum Mode: Sendable {
        /// Every request must carry a valid Cloudflare Access RS256 assertion for `issuer` and `audience`.
        case required(issuer: String, audience: String, fetchKeys: @Sendable () async throws -> [UInt8])
        /// Loopback-only local testing without Cloudflare Access (`--insecure-local-no-access`).
        case insecureLocalNoAccess
    }

    private let mode: Mode
    private var cached: (keys: AccessKeys, fetchedAt: ContinuousClock.Instant)?
    private var lastRefreshAttempt: ContinuousClock.Instant?

    package init(mode: Mode) {
        self.mode = mode
    }

    /// Standard Cloudflare Access configuration fetching keys from `https://<team>.cloudflareaccess.com/cdn-cgi/access/certs`.
    package static func cloudflare(team: String, audience: String) -> AccessVerifier {
        let clean =
            team.hasSuffix(".cloudflareaccess.com")
            ? String(team.dropLast(".cloudflareaccess.com".count))
            : team
        let issuer = "https://\(clean).cloudflareaccess.com"
        return AccessVerifier(
            mode: .required(
                issuer: issuer,
                audience: audience,
                fetchKeys: {
                    guard let certsURL = URL(string: "\(issuer)/cdn-cgi/access/certs") else {
                        throw AccessKeys.Failure.unreadable
                    }
                    let (data, _) = try await URLSession.shared.data(from: certsURL)
                    return Array(data)
                }
            )
        )
    }

    /// Checks `headers`, returning true when admitted.
    package func allows(headers: [String: String], now: Date = Date()) async -> Bool {
        switch mode {
            case .insecureLocalNoAccess:
                return true
            case .required(let issuer, let audience, let fetch):
                guard let token = ControllerHTTPRequest.accessToken(in: headers) else { return false }
                guard let keys = await currentKeys(fetch: fetch, forceRefresh: false) else { return false }
                do {
                    _ = try AccessAssertion(token, keys: keys, audience: audience, issuer: issuer, now: now)
                    return true
                } catch .unknownKey {
                    guard let refreshed = await currentKeys(fetch: fetch, forceRefresh: true) else { return false }
                    return (try? AccessAssertion(token, keys: refreshed, audience: audience, issuer: issuer, now: now))
                        != nil
                } catch {
                    return false
                }
        }
    }

    private func currentKeys(fetch: @Sendable () async throws -> [UInt8], forceRefresh: Bool) async -> AccessKeys? {
        let clock = ContinuousClock()
        let now = clock.now
        if !forceRefresh, let cached, now - cached.fetchedAt < .seconds(3_600) {
            return cached.keys
        }
        if forceRefresh, let last = lastRefreshAttempt, now - last < .seconds(30) {
            return cached?.keys
        }
        lastRefreshAttempt = now
        guard let json = try? await fetch(), let keys = try? AccessKeys(json: json) else {
            return cached?.keys
        }
        cached = (keys, now)
        return keys
    }
}
