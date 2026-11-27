internal import AemiJSON
internal import AskCore
package import Foundation
internal import Security

/// A Cloudflare Access assertion (`Cf-Access-Jwt-Assertion`, ADR-0170), checked by the gateway itself so that a request that went
/// around the tunnel is refused: an RS256 JSON Web Token signed by one of the team's keys, for the application's audience, from the
/// team's issuer, and in date.
package struct AccessAssertion: Sendable, Equatable {
    /// Why an assertion was refused.
    package enum Refusal: Error, Equatable {
        case malformed, unsupportedAlgorithm, unknownKey, badSignature, wrongAudience, wrongIssuer, expired, notYetValid
    }

    private struct Header: Decodable {
        let alg: String
        let kid: String?
    }

    private struct Claims: Decodable {
        let aud: Audience
        let iss: String
        let exp: Double
        let nbf: Double?
        let email: String?
    }

    /// `aud` is a string or a list of them.
    private struct Audience: Decodable {
        let values: [String]

        init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let one = try? container.decode(String.self) {
                values = [one]
            } else {
                values = try container.decode([String].self)
            }
        }
    }

    /// Who Access admitted, when it says.
    package let email: String?

    /// The assertion `token`, checked.
    /// - Parameters:
    ///   - token: the `Cf-Access-Jwt-Assertion` header's value.
    ///   - keys: the team's keys.
    ///   - audience: the Access application's audience tag.
    ///   - issuer: the team's domain, `https://<team>.cloudflareaccess.com`.
    ///   - now: the time to check the dates against; a minute of clock difference is allowed.
    /// - Throws: a ``Refusal`` naming the first check it failed.
    package init(_ token: String, keys: AccessKeys, audience: String, issuer: String, now: Date = Date())
        throws(Refusal)
    {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, let headerBytes = Base64URL.decode(String(parts[0])),
            let claimBytes = Base64URL.decode(String(parts[1])), let signature = Base64URL.decode(String(parts[2])),
            let header = try? AemiJSON.JSONDecoder().decode(Header.self, from: headerBytes),
            let claims = try? AemiJSON.JSONDecoder().decode(Claims.self, from: claimBytes)
        else { throw .malformed }
        guard header.alg == "RS256" else { throw .unsupportedAlgorithm }
        guard let kid = header.kid, let key = keys.key(kid) else { throw .unknownKey }
        let signed = Data((parts[0] + "." + parts[1]).utf8)
        guard
            SecKeyVerifySignature(
                key,
                .rsaSignatureMessagePKCS1v15SHA256,
                signed as CFData,
                Data(signature) as CFData,
                nil
            )
        else { throw .badSignature }
        guard claims.aud.values.contains(audience) else { throw .wrongAudience }
        guard claims.iss == issuer else { throw .wrongIssuer }
        let seconds = now.timeIntervalSince1970
        guard claims.exp + 60 > seconds else { throw .expired }
        guard (claims.nbf ?? 0) - 60 <= seconds else { throw .notYetValid }
        email = claims.email
    }
}
