internal import AskAgentCore
internal import Foundation

/// What `ask trust --agents` and `ask untrust --agents` act on (roadmap 0063 phase 3): this project's agent definitions in
/// `.agents/agents` as they are now, optionally narrowed to the names a person gave. Trust is for each file's bytes, kept under its real
/// path in the store the configuration and the skills use, so a definition that changes is untrusted until the person looks again.
enum ProjectAgentTrust {
    /// Other harnesses' folders of definitions (`agents.otherHarnesses`): under the home, and in a project.
    static let harnessFolders: [(user: String, project: String)] = [
        (".claude/agents", ".claude/agents"), (".codex/agents", ".codex/agents"), (".copilot/agents", ".github/agents")
    ]

    /// Where a project keeps its agent definitions: ask's own folder, then the other harnesses' when they are read.
    static func roots(of workspace: String, otherHarnesses: Bool = true) -> [String] {
        [workspace + "/.agents/agents"] + (otherHarnesses ? harnessFolders.map { workspace + "/" + $0.project } : [])
    }

    /// The project's definitions in `workspace`, trusted or not, narrowed to `names` when there are any.
    static func files(named names: [String], in workspace: String = FileManager.default.currentDirectoryPath)
        -> (found: [TrustedFile], missing: [String])
    {
        // Every folder a project may hold definitions in, read or not: trusting one now covers it if the setting is turned on later.
        let all = roots(of: workspace)
            .flatMap { root -> [AgentDefinition] in
                let found = AgentDiscovery.projectDefinitions(in: root, trust: SkillBook.trust())
                return found.trusted + found.untrusted
            }
            .sorted { $0.name < $1.name }
            .map {
                TrustedFile(
                    name: $0.name,
                    origin: nil,
                    file: $0.file,
                    realFile: $0.realFile,
                    digest: $0.digest,
                    description: $0.description
                )
            }
        return TrustedFile.narrowed(all, to: names, name: \.name)
    }
}
