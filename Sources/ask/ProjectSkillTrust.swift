internal import AskAgentCore
internal import Foundation

/// What `ask trust --skills` and `ask untrust --skills` act on: this project's skills as they are now, whatever their standing, optionally narrowed to
/// the names a person gave. Trust is for the file's bytes (its SHA-256, kept under the file's real path in the same store as the configuration's), so a
/// skill that changes is untrusted until the user looks again. It covers the `SKILL.md` text, which is what the model reads and what is advertised; it
/// does not cover the other files beside it, which the model may read or run only under its sandbox.
enum ProjectSkillTrust {
    /// The project's skills, all harnesses, trusted or not, as the files trust is given or taken from.
    static func files(named names: [String]) -> (found: [TrustedFile], missing: [String]) {
        let trust = SkillBook.trust()
        let catalog = SkillDiscovery.discover(
            workingDirectory: FileManager.default.currentDirectoryPath,
            home: NSHomeDirectory(),
            sources: SkillSource.standard,
            selection: SkillSelection(tokens: ["project"], knownSources: []),
            trust: trust
        )
        let all = (catalog.skills.filter { $0.scope == .project } + catalog.untrusted.map(\.skill))
            .map {
                TrustedFile(
                    name: $0.name,
                    origin: $0.source,
                    file: $0.file,
                    realFile: $0.realFile,
                    digest: $0.digest,
                    description: $0.description
                )
            }
        return TrustedFile.narrowed(all, to: names, name: \.name)
    }
}
