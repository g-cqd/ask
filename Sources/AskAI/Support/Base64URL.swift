internal import CryptoKit
internal import Foundation

/// Unpadded base64url (RFC 4648 §5).
enum Base64URL {
    static func encode(_ bytes: [UInt8]) -> String {
        Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// The bytes `text` encodes, with or without padding; nil when it is not base64url.
    static func decode(_ text: String) -> [UInt8]? {
        var base64 = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        return Data(base64Encoded: base64).map { [UInt8]($0) }
    }
}
