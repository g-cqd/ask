internal import Foundation

/// The `state` value that ties a redirect back to the sign-in that asked for it.
enum SignInState {
    /// 16 bytes from the system's cryptographic random source, as base64url: 22 characters.
    static func random() -> String {
        var random = SystemRandomNumberGenerator()
        return Base64URL.encode((0 ..< 16).map { _ in UInt8.random(in: .min ... .max, using: &random) })
    }
}
