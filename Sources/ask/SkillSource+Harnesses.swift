internal import AskAgentCore

/// The harnesses whose skill directories ask reads. Adding a harness is adding a row.
///
/// The user-level locations of every row except `ask` were found on the owner's machine (most of them symlinks to one directory). The project-level
/// locations other than `.agents/skills` come from those tools' documentation and convention and were found in no project there, so they are
/// proposals until each is checked against a real project (design note, 2026-10-24).
extension SkillSource {
    static let standard: [SkillSource] = [
        // @dl:accept -- a table of harnesses: each row is data, and they are alike because the conventions are
        SkillSource(id: "agents", userRoots: [".agents/skills"], projectRoots: [".agents/skills"], bundledRoots: []),
        // @dl:accept -- the test fixture repeats these rows on purpose: a test must not depend on the table it checks
        SkillSource(id: "ask", userRoots: [".config/ask/skills"], projectRoots: [".ask/skills"], bundledRoots: []),
        SkillSource(id: "claude", userRoots: [".claude/skills"], projectRoots: [".claude/skills"], bundledRoots: []),
        // @dl:accept -- a table of harnesses: each row is data
        SkillSource(id: "codex", userRoots: [".codex/skills"], projectRoots: [".codex/skills"], bundledRoots: []),
        SkillSource(id: "pi", userRoots: [".pi/agent/skills"], projectRoots: [".pi/skills"], bundledRoots: []),
        SkillSource(
            id: "opencode", userRoots: [".config/opencode/skills", ".config/opencode/skill"],
            // @dl:accept -- the test fixture repeats these rows on purpose: a test must not depend on the table it checks
            projectRoots: [".opencode/skills", ".opencode/skill"], bundledRoots: []),
        // @dl:accept -- a table of harnesses: each row is data
        SkillSource(id: "vibe", userRoots: [".vibe/skills"], projectRoots: [".vibe/skills"], bundledRoots: []),
        SkillSource(id: "copilot", userRoots: [".copilot/skills"], projectRoots: [".github/skills"], bundledRoots: []),
        SkillSource(
            id: "agy", userRoots: [".gemini/config/skills"], projectRoots: [".gemini/skills"],
            bundledRoots: [".gemini/antigravity-cli/builtin/skills"])
    ]

    /// The ids `from` may name, bundled included.
    static var ids: [String] { standard.map(\.id) + [bundledID] }
}
