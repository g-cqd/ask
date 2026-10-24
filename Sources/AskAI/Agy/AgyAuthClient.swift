internal import AemiJSON
internal import Foundation

/// Completes Antigravity sign-ins and refreshes credentials against Google's token endpoint, with the client secret already
/// confirmed (ADR-0066).
public struct AgyAuthClient: Sendable {
    private let transport: any HTTPTransport

    private static let errorCodes: Set = [
        "invalid_request", "invalid_client", "invalid_grant", "unauthorized_client", "unsupported_grant_type",
        "invalid_scope", "access_denied", "temporarily_unavailable"
    ]

    /// A client that sends through `transport`.
    public init(transport: any HTTPTransport) { self.transport = transport }

    /// Exchanges the code the user pasted for credentials.
    /// - Throws: ``AgyAuthError/invalidPastedCode`` before any request when the paste is not this sign-in's; otherwise a token
    ///   endpoint error or the transport's own.
    public func complete(_ pending: AgyPendingSignIn, pasted: String, secret: String, now: Double) async throws
        -> AgyCredentials
    {
        guard let code = AgyOAuth.authorizationCode(fromPasted: pasted, expectedState: pending.state) else {
            throw AgyAuthError.invalidPastedCode
        }
        let token = try await post(
            [
                ("grant_type", "authorization_code"), ("client_id", AgyOAuth.clientID), ("client_secret", secret),
                ("code", code), ("code_verifier", pending.pkce.verifier), ("redirect_uri", AgyOAuth.redirectURI)
            ])
        guard let refresh = token.refreshToken else { throw AgyAuthError.noRefreshToken }
        return AgyCredentials(
            accessToken: token.accessToken, refreshToken: refresh, expiresAt: token.expiry(from: now),
            scopes: token.scope,
            accountEmail: token.idToken.flatMap(Self.email),
            clientSecret: secret)
    }

    /// New credentials for `credentials`; what the response omits is kept, including the refresh token.
    /// - Throws: a token endpoint error or the transport's own; `invalid_grant` means signing in again.
    public func refresh(_ credentials: AgyCredentials, secret: String, now: Double) async throws -> AgyCredentials {
        let token = try await post(
            [
                ("grant_type", "refresh_token"), ("client_id", AgyOAuth.clientID), ("client_secret", secret),
                ("refresh_token", credentials.refreshToken)
            ])
        var renewed = credentials
        renewed.accessToken = token.accessToken
        renewed.refreshToken = token.refreshToken ?? credentials.refreshToken
        renewed.expiresAt = token.expiry(from: now)
        renewed.scopes = token.scope ?? credentials.scopes
        renewed.clientSecret = secret
        return renewed
    }

    private func post(_ fields: [(String, String)]) async throws -> Token {
        let request = HTTPRequest.account(
            "POST", URL(string: AgyOAuth.tokenURL)!, contentType: "application/x-www-form-urlencoded",
            body: Array(FormEncoding.query(fields).utf8))
        let reply = try await transport.collecting(request)
        guard (200 ..< 300).contains(reply.status) else {
            let code = (try? AemiJSON.parse(reply.body))?.root["error"].string
            throw AgyAuthError.tokenEndpoint(
                status: reply.status, code: code.flatMap { Self.errorCodes.contains($0) ? $0 : nil })
        }
        guard let token = try? AemiJSON.JSONDecoder().decode(Token.self, from: reply.body), token.isSound else {
            throw AgyAuthError.invalidResponse
        }
        return token
    }

    private struct Token: Decodable {
        let accessToken: String
        let expiresIn: Double
        let tokenType: String
        let refreshToken: String?
        let scope: String?
        let idToken: String?

        enum CodingKeys: String, CodingKey {
            case scope
            case accessToken = "access_token"
            case expiresIn = "expires_in"
            case tokenType = "token_type"
            case refreshToken = "refresh_token"
            case idToken = "id_token"
        }

        /// Bearer tokens of sane size without whitespace, and a positive finite lifetime that fits a date.
        var isSound: Bool {
            TokenSanity.isToken(accessToken) && (refreshToken.map(TokenSanity.isToken) ?? true)
                && tokenType.lowercased() == "bearer" && TokenSanity.isLifetime(expiresIn)
        }

        /// The time to renew by: the lifetime less a margin, so a token is never used on its last second.
        func expiry(from now: Double) -> Double { TokenSanity.renewal(from: now, lifetime: expiresIn) }
    }

    /// The conservative address shown for the account: only ordinary address characters pass, and a damaged token is nil.
    private static func email(fromIDToken token: String) -> String? {
        guard let bytes = JWTPayload.bytes(of: token),
            let address = (try? AemiJSON.parse(bytes))?.root["email"].string, address.utf16.count <= 254
        else { return nil }
        let local = address.split(separator: "@", omittingEmptySubsequences: false)
        let pattern = #"^[A-Za-z0-9._%+'-]{1,64}@[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,24}$"#
        guard local.count == 2, address.range(of: pattern, options: .regularExpression) != nil else { return nil }
        return address
    }
}
