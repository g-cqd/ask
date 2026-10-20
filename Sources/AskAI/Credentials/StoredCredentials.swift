/// The stored envelope, kept separate from its transactional file owner so evolving records have one encoding owner.
struct StoredCredentials: Codable {
    var claude: ClaudeCredentials?
    var keys: [String: StoredKey]?
    var codex: CodexCredentials?
}
