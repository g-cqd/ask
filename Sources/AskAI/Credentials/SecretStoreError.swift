/// Why a secret store refused.
public enum SecretStoreError: Error, Sendable, Equatable {
    /// The store answered with this status (an `OSStatus` for the Keychain).
    case failed(status: Int32)
    /// The item exists but is not what this ask wrote.
    case unreadable
}
