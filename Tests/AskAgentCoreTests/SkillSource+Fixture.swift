@testable import AskAgentCore

extension SkillSource {
    /// A table for tests: the harnesses the discovery tests put skills under. (The shipped table is in the composition root.)
    static let fixture: [SkillSource] = [
        SkillSource(id: "agents", userRoots: [".agents/skills"], projectRoots: [".agents/skills"], bundledRoots: []),
        SkillSource(id: "claude", userRoots: [".claude/skills"], projectRoots: [".claude/skills"], bundledRoots: []),
        SkillSource(id: "codex", userRoots: [".codex/skills"], projectRoots: [".codex/skills"], bundledRoots: []),
        SkillSource(id: "pi", userRoots: [".pi/agent/skills"], projectRoots: [".pi/skills"], bundledRoots: []),
        SkillSource(
            id: "opencode", userRoots: [".config/opencode/skills", ".config/opencode/skill"],
            projectRoots: [".opencode/skills"], bundledRoots: []),
        SkillSource(id: "vibe", userRoots: [".vibe/skills"], projectRoots: [".vibe/skills"], bundledRoots: []),
        SkillSource(id: "copilot", userRoots: [".copilot/skills"], projectRoots: [".github/skills"], bundledRoots: []),
        SkillSource(
            id: "agy", userRoots: [".gemini/config/skills"], projectRoots: [".gemini/skills"],
            bundledRoots: [".gemini/antigravity-cli/builtin/skills"])
    ]

    static var fixtureIDs: [String] { fixture.map(\.id) }
}
