internal import AskAgentCore
internal import Foundation

/// What `ask trust --agents` and `ask untrust --agents` act on (roadmap 0063 phase 3): this project's agent definitions in
/// `.agents/agents` as they are now, optionally narrowed to the names a person gave. Trust is for each file's bytes, kept under its real
/// path in the store the configuration and the skills use, so a definition that changes is untrusted until the person looks again.
enum ProjectAgentTrust {
    /// Where a project keeps its agent definitions.
    static func root(of workspace: String) -> String { workspace + "/.agents/agents" }

    /// The project's definitions in `workspace`, trusted or not, narrowed to `names` when there are any.
    static func files(named names: [String], in workspace: String = FileManager.default.currentDirectoryPath)
        -> (found: [TrustedFile], missing: [String])
    {
        let found = AgentDiscovery.projectDefinitions(in: root(of: workspace), trust: SkillBook.trust())
        let all = (found.trusted + found.untrusted).sorted { $0.name < $1.name }
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
