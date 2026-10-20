internal import Foundation

extension CredentialFile {
    /// Reads a credential and its registration in the same snapshot; a rename is not a change of authority.
    func load<T>(_ record: KeyPath<StoredCredentials, T?>, connection: ConnectionRecord?) throws(CredentialFileError)
        -> T?
    {
        let stored = try read()
        guard matches(connection, stored) else { throw .connectionChanged(path: url.path) }
        return stored?[keyPath: record]
    }

    /// Unnamed legacy callers retain their old behavior; named callers must still hold the selected authorization.
    func matches(_ expected: ConnectionRecord?, _ stored: StoredCredentials?) -> Bool {
        guard let expected else { return true }
        guard let actual = stored?.connection else { return false }
        return actual.id == expected.id && actual.authorizationID == expected.authorizationID
            && actual.provider == expected.provider && !actual.removed
    }
}
