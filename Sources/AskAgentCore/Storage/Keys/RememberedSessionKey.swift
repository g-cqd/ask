internal import AskAI
internal import CryptoKit
internal import Foundation

/// "Remember" (ADR-0138, section 4): the user key kept in the keychain (ask's ``SecretStore``, roadmap 0110), so no password is asked
/// and nothing is derived at start. It is recalled only when it hashes to `keys.json`'s key identifier, so a key left from an earlier
/// `keys.json`, or a changed item, is never used.
enum RememberedSessionKey {
    static let account = "session-encryption"

    static func remember(_ userKey: SymmetricKey, in store: any SecretStore) throws(SecretStoreError) {
        let encoded = userKey.withUnsafeBytes { Data($0).base64EncodedString() }
        try store.store(["userKey": encoded], for: account)
    }

    static func recall(keyID: Data, from store: any SecretStore) throws(SecretStoreError) -> SymmetricKey? {
        guard let encoded = try store.secrets(for: account)?["userKey"], let bytes = Data(base64Encoded: encoded),
            bytes.count == 32
        else { return nil }
        let key = SymmetricKey(data: bytes)
        return Data(SessionKeys.identifier(of: key)) == keyID ? key : nil
    }

    static func forget(in store: any SecretStore) throws(SecretStoreError) {
        try store.remove(account: account)
    }
}
