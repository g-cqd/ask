internal import AskAI
internal import CryptoKit
internal import Foundation

/// This computer's gateway key (ADR-0170): an X25519 key made once and kept in the keychain (roadmap 0110), never in a file.
enum GatewayNodeKey {
    /// The keychain account it is kept under.
    static let account = "gateway/node"

    /// Why the key could not be read.
    struct Unreadable: Error, CustomStringConvertible {
        var description: String { "the gateway key in the keychain cannot be read" }
    }

    /// The key kept in `store`, made and kept the first time.
    static func loadOrCreate(in store: any SecretStore) throws -> Curve25519.KeyAgreement.PrivateKey {
        if let secrets = try store.secrets(for: account) {
            guard let encoded = secrets["x25519"], let bytes = Data(base64Encoded: encoded),
                let key = try? Curve25519.KeyAgreement.PrivateKey(rawRepresentation: bytes)
            else { throw Unreadable() }
            return key
        }
        let key = Curve25519.KeyAgreement.PrivateKey()
        try store.store(["x25519": key.rawRepresentation.base64EncodedString()], for: account)
        return key
    }
}
