internal import CryptoKit
internal import Foundation

/// An RFC 7636 S256 verifier and its challenge. A fresh pair for every sign-in attempt.
public struct PKCE: Sendable, Equatable {
    public let verifier: String
    public let challenge: String

    /// The pair for `verifier`.
    public init(verifier: String) {
        self.verifier = verifier
        challenge = Base64URL.encode(Array(SHA256.hash(data: Array(verifier.utf8))))
    }

    /// A pair from 32 bytes of the system's cryptographic random source.
    public static func generate() -> PKCE {
        var random = SystemRandomNumberGenerator()
        return PKCE(verifier: Base64URL.encode((0 ..< 32).map { _ in UInt8.random(in: .min ... .max, using: &random) }))
    }
}
