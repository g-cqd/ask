/// Other agents' sign-ins, kept unreadable by the sandbox like the other secret stores (security audit 2026-10-29, finding 2), relative
/// to the home: Codex's, Gemini's, Copilot's and Claude Code's. Named here, the composition root, since they name providers.
enum OtherAgentsSecrets {
    static let directories = [".codex", ".gemini", ".config/github-copilot"]
    static let files = [".claude/.credentials.json"]
}
