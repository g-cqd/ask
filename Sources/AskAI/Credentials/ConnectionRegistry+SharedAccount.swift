extension ConnectionRegistry {
    /// The names of the registered connections currently signed in as `identity`, sorted.
    ///
    /// Identity is what each connection's stored credentials say, so a connection that is signed out, removed or has an unreadable
    /// credential file holds no account and is left out: this is a notice, and a damaged neighbour must not stop it. (The listing
    /// already omits removed registrations and sorts by name, and a Codex lookup on a Claude connection finds no Codex record, so
    /// none of those needs a filter here.)
    /// - Parameters:
    ///   - identity: the account.
    ///   - excluding: a connection to leave out, usually the one just signed in.
    /// - Returns: the other holders' names.
    /// - Throws: when the registry itself cannot be listed.
    public func connections(as identity: AccountIdentity, excluding: ConnectionRecord? = nil) throws -> [String] {
        try list().records
            .filter { $0.id != excluding?.id }
            .filter { record in (try? credentials(for: record).isSignedIn(as: identity, connection: record)) == true }
            .map(\.name)
    }
}
