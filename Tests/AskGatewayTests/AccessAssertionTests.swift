internal import AskCore
internal import Foundation
internal import Security
internal import Testing

@testable import AskGateway

/// The gateway checks Cloudflare Access's assertion itself (ADR-0170), with tokens signed here by a fresh RSA key published as a JSON
/// Web Key Set: a good one passes, and a wrong signature, key id, audience, issuer, algorithm or date is refused.
struct AccessAssertionTests {
    private static let audience = "aud-tag-123"
    private static let issuer = "https://team.cloudflareaccess.com"

    private struct Signer {
        let key: SecKey
        let set: [UInt8]

        init() throws {
            let attributes: [CFString: Any] = [kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeySizeInBits: 2_048]
            guard let key = SecKeyCreateRandomKey(attributes as CFDictionary, nil),
                let publicKey = SecKeyCopyPublicKey(key),
                let der = SecKeyCopyExternalRepresentation(publicKey, nil) as Data?
            else { throw POSIXError(.EINVAL) }
            self.key = key
            let (modulus, exponent) = try Self.read(Array(der))
            set = Array(
                #"{"keys":[{"kid":"k1","kty":"RSA","alg":"RS256","n":"\#(Base64URL.encode(modulus))","e":"\#(Base64URL.encode(exponent))"},{"kid":"x","kty":"EC"}]}"#
                    .utf8
            )
        }

        /// The modulus and exponent of a PKCS #1 RSAPublicKey: a SEQUENCE of two INTEGERs.
        static func read(_ der: [UInt8]) throws -> ([UInt8], [UInt8]) {
            var index = 0
            func length() -> Int {
                let first = Int(der[index])
                index += 1
                guard first & 0x80 != 0 else { return first }
                var value = 0
                for _ in 0 ..< (first & 0x7F) {
                    value = value << 8 | Int(der[index])
                    index += 1
                }
                return value
            }
            func integer() -> [UInt8] {
                index += 1
                let count = length()
                defer { index += count }
                return Array(der[index ..< index + count])
            }
            index = 1
            _ = length()
            return (integer(), integer())
        }

        func token(header: String = #"{"alg":"RS256","kid":"k1"}"#, claims: [String: Any]) throws -> String {
            let body = try JSONSerializationFree.encode(claims)
            let signing = Base64URL.encode(Array(header.utf8)) + "." + Base64URL.encode(Array(body.utf8))
            guard
                let signature = SecKeyCreateSignature(
                    key,
                    .rsaSignatureMessagePKCS1v15SHA256,
                    Data(signing.utf8) as CFData,
                    nil
                ) as Data?
            else { throw POSIXError(.EINVAL) }
            return signing + "." + Base64URL.encode(Array(signature))
        }
    }

    /// A claims object written by hand, so this test needs no JSON library: strings, numbers, and a list of strings.
    private enum JSONSerializationFree {
        static func encode(_ claims: [String: Any]) throws -> String {
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
    }

    private static let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func claims(_ changes: [String: Any] = [:]) -> [String: Any] {
        var claims: [String: Any] = [
            "aud": [Self.audience], "iss": Self.issuer, "exp": Self.now.timeIntervalSince1970 + 3_600,
            "nbf": Self.now.timeIntervalSince1970 - 10, "email": "someone@example.com"
        ]
        for (key, value) in changes { claims[key] = value }
        return claims
    }

    private func check(_ token: String, _ signer: Signer) throws -> AccessAssertion {
        try AccessAssertion(
            token,
            keys: try AccessKeys(json: signer.set),
            audience: Self.audience,
            issuer: Self.issuer,
            now: Self.now
        )
    }

    @Test func `a good assertion passes, and names who Access admitted`() throws {
        let signer = try Signer()
        #expect(try check(try signer.token(claims: claims()), signer).email == "someone@example.com")
        #expect(try AccessKeys(json: signer.set).keys.keys.sorted() == ["k1"], "a key of another kind is left out")
    }

    @Test func `anything else is refused`() throws {
        let signer = try Signer()
        let other = try Signer()
        let cases: [(String, AccessAssertion.Refusal)] = [
            (try other.token(claims: claims()), .badSignature),
            (try signer.token(header: #"{"alg":"RS256","kid":"k2"}"#, claims: claims()), .unknownKey),
            (try signer.token(header: #"{"alg":"none","kid":"k1"}"#, claims: claims()), .unsupportedAlgorithm),
            (try signer.token(claims: claims(["aud": ["another"]])), .wrongAudience),
            (try signer.token(claims: claims(["iss": "https://evil.cloudflareaccess.com"])), .wrongIssuer),
            (try signer.token(claims: claims(["exp": Self.now.timeIntervalSince1970 - 120])), .expired),
            (try signer.token(claims: claims(["nbf": Self.now.timeIntervalSince1970 + 120])), .notYetValid),
            ("not.a.token", .malformed)
        ]
        for (token, refusal) in cases {
            #expect(throws: refusal) { _ = try check(token, signer) }
        }
    }

    @Test func `the key built from n and e is the key that signed`() throws {
        let signer = try Signer()
        let built = try #require(try AccessKeys(json: signer.set).key("k1"))
        let original = try #require(SecKeyCopyPublicKey(signer.key))
        #expect(
            SecKeyCopyExternalRepresentation(built, nil) as Data? == SecKeyCopyExternalRepresentation(original, nil)
                as Data?
        )
    }
}
