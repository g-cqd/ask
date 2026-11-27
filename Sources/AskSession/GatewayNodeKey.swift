package import AskAI
package import CryptoKit
internal import Foundation

/// Keys kept in the keychain for the gateway (ADR-0170, roadmap 0110), never in a file: a node's X25519 key (`gateway/node`), the
/// gateway server's X25519 key (`gateway/server`), and the Ed25519 key that signs the web shell (`gateway/shell-signing`).
package enum GatewayNodeKey {
    package static let account = "gateway/node"
    package static let serverAccount = "gateway/server"
    package static let shellSigningAccount = "gateway/shell-signing"

    /// Why the key could not be read.
    package struct Unreadable: Error, CustomStringConvertible {
        package var description: String { "the gateway key in the keychain cannot be read" }
    }

    /// The X25519 key under `account` in `store`, made and kept the first time.
    package static func loadOrCreate(
        account: String = account,
        in store: any SecretStore
    ) throws -> Curve25519.KeyAgreement.PrivateKey {
        try Curve25519.KeyAgreement.PrivateKey(
            rawRepresentation: raw32(account: account, field: "x25519", in: store)
        )
    }

    /// The Ed25519 signing key under `shellSigningAccount` in `store`, made and kept the first time.
    package static func loadOrCreateSigningKey(in store: any SecretStore) throws -> Curve25519.Signing.PrivateKey {
        try Curve25519.Signing.PrivateKey(
            rawRepresentation: raw32(account: shellSigningAccount, field: "ed25519", in: store)
        )
    }

    private static func raw32(account: String, field: String, in store: any SecretStore) throws -> Data {
        if let secrets = try store.secrets(for: account) {
            guard let encoded = secrets[field], let bytes = Data(base64Encoded: encoded), bytes.count == 32 else {
                throw Unreadable()
            }
            return bytes
        }
        var random = [UInt8](repeating: 0, count: 32)
        for index in random.indices { random[index] = UInt8.random(in: 0 ... 255) }
        let data = Data(random)
        try store.store([field: data.base64EncodedString()], for: account)
        return data
    }
}
