/// Where the secrets of the credential file are kept when they are not in the file (roadmap 0110): one item per record, named by the
/// file's path and the record, holding that record's secret fields. The Keychain in use; a store in memory in tests.
public protocol SecretStore: Sendable {
    /// The secret fields stored for `account`, or nil when there is no item.
    func secrets(for account: String) throws(SecretStoreError) -> [String: String]?
    /// Creates or replaces the item for `account`.
    func store(_ secrets: [String: String], for account: String) throws(SecretStoreError)
    /// Removes the item for `account`; none is not an error.
    func remove(account: String) throws(SecretStoreError)
}
