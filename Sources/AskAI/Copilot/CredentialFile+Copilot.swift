// @dl:accept -- typed record accessors intentionally mirror other providers over the shared transactional key-path implementation
extension CredentialFile {
    public func loadCopilot() throws(CredentialFileError) -> CopilotCredentials? { try read()?.copilot }
    public func saveCopilot(_ value: CopilotCredentials) throws(CredentialFileError) { try save(\.copilot, value) }
    public func saveCopilot(_ value: CopilotCredentials, ifStill expected: CopilotCredentials)
        throws(CredentialFileError) -> Bool
    {
        try replace(\.copilot, with: value, ifStill: expected, connection: nil)
    }
}
