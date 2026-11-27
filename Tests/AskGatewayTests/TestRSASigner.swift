internal import AskCore
internal import Foundation
internal import Security

@testable import AskGateway

/// Ephemeral 2048-bit RSA signer and JWKS generator for testing Cloudflare Access RS256 token verification in `AskGatewayTests`.
struct TestRSASigner: Sendable {
    let kid: String
    private let privateDER: Data
    let publicDER: Data
    let jwkJSON: String

    init(kid: String = "k1") throws {
        self.kid = kid
        let attributes: [CFString: Any] = [kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeySizeInBits: 2_048]
        guard let key = SecKeyCreateRandomKey(attributes as CFDictionary, nil),
            let privData = SecKeyCopyExternalRepresentation(key, nil) as Data?,
            let pub = SecKeyCopyPublicKey(key),
            let pubData = SecKeyCopyExternalRepresentation(pub, nil) as Data?
        else { throw POSIXError(.EINVAL) }
        privateDER = privData
        publicDER = pubData
        let (modulus, exponent) = Self.readPKCS1Public(Array(pubData))
        jwkJSON =
            #"{"kid":"\#(kid)","kty":"RSA","alg":"RS256","n":"\#(Base64URL.encode(modulus))","e":"\#(Base64URL.encode(exponent))"}"#
    }

    var jwksWithIgnoredEC: [UInt8] {
        Array(#"{"keys":[\#(jwkJSON),{"kid":"x","kty":"EC"}]}"#.utf8)
    }

    func sign(header: String? = nil, claimsJSON: String) throws -> String {
        let head = header ?? #"{"alg":"RS256","kid":"\#(kid)"}"#
        let attrs: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeyClass: kSecAttrKeyClassPrivate
        ]
        guard let key = SecKeyCreateWithData(privateDER as CFData, attrs as CFDictionary, nil) else {
            throw POSIXError(.EINVAL)
        }
        let signing = Base64URL.encode(Array(head.utf8)) + "." + Base64URL.encode(Array(claimsJSON.utf8))
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

    private static func readPKCS1Public(_ der: [UInt8]) -> ([UInt8], [UInt8]) {
        var index = 1
        func length() -> Int {
            let first = Int(der[index])
            index += 1
            guard first & 0x80 != 0 else { return first }
            var value = 0
            for _ in 0 ..< (first & 0x7F) {
                value = (value << 8) | Int(der[index])
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
        _ = length()
        return (integer(), integer())
    }
}
