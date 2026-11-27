internal import Foundation
internal import Security
internal import Testing

@testable import AskGateway

/// The gateway checks Cloudflare Access's assertion itself (ADR-0170), with tokens signed here by a fresh RSA key published as a JSON
/// Web Key Set: a good one passes, and a wrong signature, key id, audience, issuer, algorithm or date is refused.
struct AccessAssertionTests {
    private static let audience = "aud-tag-123"
    private static let issuer = "https://team.cloudflareaccess.com"
    private static let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func claimsJSON(_ changes: [String: Any] = [:]) -> String {
        var claims: [String: Any] = [
            "aud": [Self.audience], "iss": Self.issuer, "exp": Self.now.timeIntervalSince1970 + 3_600,
            "nbf": Self.now.timeIntervalSince1970 - 10, "email": "someone@example.com"
        ]
        for (key, value) in changes { claims[key] = value }
        let fields = claims.sorted { $0.key < $1.key }
            .map { key, value -> String in
                switch value {
                    case let text as String: "\"\(key)\":\"\(text)\""
                    case let list as [String]:
                        "\"\(key)\":[" + list.map { "\"\($0)\"" }.joined(separator: ",") + "]"
                    case let number as Double: "\"\(key)\":\(Int(number))"
                    default: ""
                }
            }
        return "{" + fields.joined(separator: ",") + "}"
    }

    private func check(_ token: String, _ signer: TestRSASigner) throws -> AccessAssertion {
        try AccessAssertion(
            token,
            keys: try AccessKeys(json: signer.jwksWithIgnoredEC),
            audience: Self.audience,
            issuer: Self.issuer,
            now: Self.now
        )
    }

    @Test func `a good assertion passes, and names who Access admitted`() throws {
        let signer = try TestRSASigner()
        #expect(try check(try signer.sign(claimsJSON: claimsJSON()), signer).email == "someone@example.com")
        #expect(try AccessKeys(json: signer.jwksWithIgnoredEC).keys.keys.sorted() == ["k1"])
    }

    @Test func `anything else is refused`() throws {
        let signer = try TestRSASigner()
        let other = try TestRSASigner()
        let cases: [(String, AccessAssertion.Refusal)] = [
            (try other.sign(claimsJSON: claimsJSON()), .badSignature),
            (try signer.sign(header: #"{"alg":"RS256","kid":"k2"}"#, claimsJSON: claimsJSON()), .unknownKey),
            (try signer.sign(header: #"{"alg":"none","kid":"k1"}"#, claimsJSON: claimsJSON()), .unsupportedAlgorithm),
            (try signer.sign(claimsJSON: claimsJSON(["aud": ["another"]])), .wrongAudience),
            (try signer.sign(claimsJSON: claimsJSON(["iss": "https://evil.cloudflareaccess.com"])), .wrongIssuer),
            (try signer.sign(claimsJSON: claimsJSON(["exp": Self.now.timeIntervalSince1970 - 120])), .expired),
            (try signer.sign(claimsJSON: claimsJSON(["nbf": Self.now.timeIntervalSince1970 + 120])), .notYetValid),
            ("not.a.token", .malformed)
        ]
        for (token, refusal) in cases {
            #expect(throws: refusal) { _ = try check(token, signer) }
        }
    }

    @Test func `the key built from n and e is the key that signed`() throws {
        let signer = try TestRSASigner()
        let built = try #require(try AccessKeys(json: signer.jwksWithIgnoredEC).key("k1"))
        #expect(SecKeyCopyExternalRepresentation(built, nil) as Data? == signer.publicDER)
    }
}
