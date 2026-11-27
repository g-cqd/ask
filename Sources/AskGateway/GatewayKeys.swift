internal import AskCore
package import CryptoKit
internal import Foundation

/// How gateway keys are written for a person: a public key as base64 or hex, and a fingerprint to compare by eye.
package enum GatewayKeys {
    /// The fingerprint a person compares: the first 16 bytes of the key's SHA-256, as 8 groups of 4 hex digits.
    package static func fingerprint(_ key: Curve25519.KeyAgreement.PublicKey) -> String {
        fingerprint(rawRepresentation: key.rawRepresentation)
    }

    /// The fingerprint of raw 32-byte public-key bytes, for X25519 or Ed25519 keys alike.
    static func fingerprint(rawRepresentation: Data) -> String {
        let hex = SHA256.hash(data: rawRepresentation).prefix(16).map { String(format: "%02x", $0) }.joined()
        return stride(from: 0, to: hex.count, by: 4)
            .map { offset in
                let start = hex.index(hex.startIndex, offsetBy: offset)
                return String(hex[start ..< hex.index(start, offsetBy: 4)])
            }
            .joined(separator: " ")
    }

    /// A public key written as base64 (standard or URL-safe, padded or not) or as 64 hex digits; nil for anything else.
    package static func publicKey(_ text: String) -> Curve25519.KeyAgreement.PublicKey? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var bytes: [UInt8]?
        if text.count == 64, text.allSatisfy(\.isHexDigit) {
            bytes = stride(from: 0, to: 64, by: 2)
                .compactMap { offset in
                    let start = text.index(text.startIndex, offsetBy: offset)
                    return UInt8(text[start ..< text.index(start, offsetBy: 2)], radix: 16)
                }
        } else {
            bytes = Base64URL.decode(text)
        }
        guard let bytes, bytes.count == 32 else { return nil }
        return try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: bytes)
    }
}
