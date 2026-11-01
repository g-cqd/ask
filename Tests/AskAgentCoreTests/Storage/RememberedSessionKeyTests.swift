import AskAI
import CryptoKit
import Foundation
import Synchronization
import Testing

@testable import AskAgentCore

/// "Remember": the user key in the keychain (ADR-0138, section 4), recalled only for the `keys.json` it belongs to.
@Suite
struct RememberedSessionKeyTests {
    final class Kept: SecretStore {
        let items = Mutex<[String: [String: String]]>([:])
        func secrets(for account: String) throws(SecretStoreError) -> [String: String]? {
            items.withLock { $0[account] }
        }
        func store(_ secrets: [String: String], for account: String) throws(SecretStoreError) {
            items.withLock { $0[account] = secrets }
        }
        func remove(account: String) throws(SecretStoreError) { _ = items.withLock { $0.removeValue(forKey: account) } }
    }

    @Test
    func `a remembered key is recalled for its own keys only, and forgotten on request`() throws {
        let store = Kept()
        let key = SymmetricKey(size: .bits256)
        let keyID = Data(SessionKeys.identifier(of: key))
        try RememberedSessionKey.remember(key, in: store)
        #expect(try RememberedSessionKey.recall(keyID: keyID, from: store) == key)
        #expect(try RememberedSessionKey.recall(keyID: Data(repeating: 0, count: 16), from: store) == nil)
        try RememberedSessionKey.forget(in: store)
        #expect(try RememberedSessionKey.recall(keyID: keyID, from: store) == nil)
    }

    @Test
    func `a kept value that is not the key it says it is is not used`() throws {
        let store = Kept()
        let key = SymmetricKey(size: .bits256)
        let keyID = Data(SessionKeys.identifier(of: key))
        try RememberedSessionKey.remember(key, in: store)
        let other = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0).base64EncodedString() }
        store.items.withLock { $0[RememberedSessionKey.account]?["userKey"] = other }
        #expect(try RememberedSessionKey.recall(keyID: keyID, from: store) == nil)
    }
}
