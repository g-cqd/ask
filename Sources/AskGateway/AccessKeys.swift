internal import AemiJSON
internal import AskCore
internal import Foundation
package import Security

/// The keys Cloudflare Access signs its assertions with (ADR-0170): the team's JSON Web Key Set, at
/// `https://<team>.cloudflareaccess.com/cdn-cgi/access/certs`, RSA keys by key id.
package struct AccessKeys: Sendable {
    /// Why a key set could not be read.
    package enum Failure: Error, Equatable {
        case unreadable
        case noKeys
    }

    private struct JWKSet: Decodable {
        struct Key: Decodable {
            let kid: String?
            let kty: String
            let n: String?  // swiftlint:disable:this identifier_name
            let e: String?  // swiftlint:disable:this identifier_name
        }

        let keys: [Key]
    }

    /// The RSA keys, by key id, each an `RSAPublicKey` in DER (PKCS #1): Security's keys are not sendable, so they are made when used.
    package let keys: [String: [UInt8]]

    /// The RSA keys of a JSON Web Key Set; keys of other kinds, without an id, or that Security does not read, are left out.
    package init(json: [UInt8]) throws(Failure) {
        guard let set = try? AemiJSON.JSONDecoder().decode(JWKSet.self, from: json) else { throw .unreadable }
        var keys: [String: [UInt8]] = [:]
        for key in set.keys where key.kty == "RSA" {
            guard let kid = key.kid, let modulus = key.n.flatMap(Base64URL.decode),
                let exponent = key.e.flatMap(Base64URL.decode)
            else { continue }
            let der = DER.sequence(DER.integer(modulus) + DER.integer(exponent))
            if Self.publicKey(der) != nil { keys[kid] = der }
        }
        guard !keys.isEmpty else { throw .noKeys }
        self.keys = keys
    }

    /// Key `kid`, as Security takes it; nil when there is none.
    package func key(_ kid: String) -> SecKey? { keys[kid].flatMap(Self.publicKey) }

    /// The RSA public key in `der`, an `RSAPublicKey`; nil when Security does not read it.
    private static func publicKey(_ der: [UInt8]) -> SecKey? {
        let attributes: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeyClass: kSecAttrKeyClassPublic
        ]
        return SecKeyCreateWithData(Data(der) as CFData, attributes as CFDictionary, nil)
    }
}
