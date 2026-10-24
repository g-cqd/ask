extension CredentialFile {
    /// Whether the default sign-in holds `identity`.
    /// - Throws: ``CredentialFileError`` when the file is damaged or exposed.
    public func isSignedIn(as identity: AccountIdentity) throws(CredentialFileError) -> Bool {
        try isSignedIn(as: identity, connection: nil)
    }

    func isSignedIn(as identity: AccountIdentity, connection: ConnectionRecord?) throws(CredentialFileError) -> Bool {
        switch identity {
            case .codex(let id): return try loadCodex(connection: connection)?.accountID == id
            case .claude(let email):
                return try loadClaude(connection: connection)?.accountEmail?.lowercased() == email.lowercased()
        }
    }
}
