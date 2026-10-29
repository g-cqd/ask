import Synchronization

@testable import AskAI

/// A secret store that keeps items in memory, for the file's logic: what goes where, and when.
final class MemorySecretStore: SecretStore {
    let items = Mutex<[String: [String: String]]>([:])
    let failWrites = Mutex(false)

    func secrets(for account: String) throws(SecretStoreError) -> [String: String]? { items.withLock { $0[account] } }

    func store(_ secrets: [String: String], for account: String) throws(SecretStoreError) {
        if failWrites.withLock({ $0 }) { throw .failed(status: -1) }
        items.withLock { $0[account] = secrets }
    }

    func remove(account: String) throws(SecretStoreError) { _ = items.withLock { $0.removeValue(forKey: account) } }
}
