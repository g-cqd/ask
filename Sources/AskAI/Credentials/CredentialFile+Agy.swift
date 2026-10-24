/// Antigravity's sign-in beside the other providers' records, through the same transactions.
extension CredentialFile {
    /// The stored Antigravity credentials, or nil when there are none.
    /// - Throws: ``CredentialFileError/exposed(path:mode:)`` or ``CredentialFileError/damaged(path:)``.
    public func loadAgy() throws(CredentialFileError) -> AgyCredentials? { try read()?.agy }

    /// Stores Antigravity credentials, replacing any, whole, and keeping every other provider's.
    /// - Throws: ``CredentialFileError/io(path:errno:)``, or ``CredentialFileError/damaged(path:)``, which is never overwritten.
    public func saveAgy(_ credentials: AgyCredentials) throws(CredentialFileError) { try save(\.agy, credentials) }

    /// Stores `credentials` only if the stored ones are still `expected`.
    /// - Returns: false when they changed or were removed meanwhile, and nothing was written.
    /// - Throws: as ``saveAgy(_:)``.
    public func saveAgy(_ credentials: AgyCredentials, ifStill expected: AgyCredentials) throws(CredentialFileError)
        -> Bool
    {
        try replace(\.agy, with: credentials, ifStill: expected, connection: nil)
    }

    /// Removes Antigravity's credentials, keeping every other provider's. Nothing stored is not an error.
    /// - Throws: as ``saveAgy(_:)``.
    public func removeAgy() throws(CredentialFileError) { try clear(\.agy) }
}
