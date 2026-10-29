public import Foundation
internal import Security

/// Secrets as generic password items in the Keychain (roadmap 0110): service `ask`, account the file's path and record, the value the
/// record's secret fields as JSON. Access is bound by the Keychain to the signature of the binary that created the item, so a build
/// signed with a stable identity reads its items with no prompt, and anything else (another program, `security` run by a model's
/// command) is asked about. The legacy keychain: the data-protection one needs an entitlement only a provisioning profile grants.
public struct KeychainSecretStore: SecretStore {
    public let service: String
    /// A keychain file to keep the items in instead of the person's default keychain: for tests.
    private let keychain: Keychain?

    /// - Parameters:
    ///   - service: the items' service attribute.
    ///   - keychainPath: a keychain file to use instead of the default one; nil for the default.
    /// - Throws: ``SecretStoreError/failed(status:)`` when the keychain file cannot be opened.
    public init(service: String = "ask", keychainPath: String? = nil) throws(SecretStoreError) {
        self.service = service
        // A keychain file for end-to-end tests, so a run of the real binary never touches the person's keychain.
        let keychainPath =
            keychainPath
            ?? ProcessInfo.processInfo.environment["ASK_KEYCHAIN_PATH"].flatMap { $0.hasPrefix("/") ? $0 : nil }
        if let keychainPath {
            var reference: CFTypeRef?
            let status = keychainPath.withCString { askSecKeychainOpen($0, &reference) }
            guard status == errSecSuccess, let reference else { throw .failed(status: status) }
            keychain = Keychain(reference: reference)
        } else {
            keychain = nil
        }
    }

    public func secrets(for account: String) throws(SecretStoreError) -> [String: String]? {
        var query = base(account)
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw .failed(status: status) }
        guard let data = result as? Data, let value = try? JSONDecoder().decode([String: String].self, from: data)
        else {
            throw .unreadable
        }
        return value
    }

    public func store(_ secrets: [String: String], for account: String) throws(SecretStoreError) {
        guard let data = try? JSONEncoder().encode(secrets) else { throw .unreadable }
        let update = SecItemUpdate(base(account) as CFDictionary, [kSecValueData: data] as CFDictionary)
        if update == errSecSuccess { return }
        guard update == errSecItemNotFound else { throw .failed(status: update) }
        var attributes = base(account, forAdding: true)
        attributes[kSecValueData] = data
        attributes[kSecAttrLabel] = "ask credentials"
        let add = SecItemAdd(attributes as CFDictionary, nil)
        guard add == errSecSuccess else { throw .failed(status: add) }
    }

    public func remove(account: String) throws(SecretStoreError) {
        let status = SecItemDelete(base(account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw .failed(status: status) }
    }

    /// The query naming one item, in the chosen keychain.
    private func base(_ account: String, forAdding: Bool = false) -> [CFString: Any] {
        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account
        ]
        if let keychain {
            if forAdding {
                query[kSecUseKeychain] = keychain.reference
            } else {
                query[kSecMatchSearchList] = [keychain.reference]
            }
        }
        return query
    }

    /// An open keychain file. `SecKeychain` is deprecated as a type, not as a capability: items in a given file are still reached through
    /// it, and tests need that file to keep off the person's keychain.
    // SAFETY: a SecKeychain reference is immutable once opened, and the Security framework's item calls are thread-safe.
    private struct Keychain: @unchecked Sendable {
        let reference: CFTypeRef
    }
}

/// `SecKeychainOpen`, declared here so a test keychain file can be opened without the deprecated type's name in the signature.
@_silgen_name("SecKeychainOpen")
private func askSecKeychainOpen(_ path: UnsafePointer<CChar>, _ keychain: UnsafeMutablePointer<CFTypeRef?>) -> OSStatus
