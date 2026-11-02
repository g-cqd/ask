/// MCP servers' sign-ins beside the providers' records, through the same transactions (roadmap 0067).
extension CredentialFile {
    /// The sign-in to the server at `server` (its canonical address), or nil when there is none.
    /// - Throws: ``CredentialFileError/exposed(path:mode:)`` or ``CredentialFileError/damaged(path:)``.
    public func loadMCP(server: String) throws(CredentialFileError) -> MCPServerCredentials? {
        try read()?.mcp?[server]
    }

    /// Stores `record`, replacing the server's previous one and keeping every other record.
    /// - Throws: ``CredentialFileError/io(path:errno:)``, or ``CredentialFileError/damaged(path:)``, which is never overwritten.
    public func saveMCP(_ record: MCPServerCredentials) throws(CredentialFileError) {
        try transact(creating: true) {
            $0.mcp = ($0.mcp ?? [:]).merging([record.server: record]) { _, new in new }
            return ((), true)
        }
    }

    /// Removes the sign-in to `server`, keeping every other record. Nothing stored is not an error.
    /// - Throws: as ``saveMCP(_:)``.
    public func removeMCP(server: String) throws(CredentialFileError) {
        try transact(creating: false) {
            guard $0.mcp?[server] != nil else { return ((), false) }
            $0.mcp?[server] = nil
            if $0.mcp?.isEmpty == true { $0.mcp = nil }
            return ((), true)
        }
    }
}
