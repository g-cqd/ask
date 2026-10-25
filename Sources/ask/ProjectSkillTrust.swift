internal import AskAgentCore
internal import Foundation

/// What `ask trust --skills` and `ask untrust --skills` act on: this project's skills as they are now, whatever their standing, optionally narrowed to
/// the names a person gave. Trust is for the file's bytes (its SHA-256, kept under the file's real path in the same store as the configuration's), so a
/// skill that changes is untrusted until the user looks again. It covers the `SKILL.md` text, which is what the model reads and what is advertised; it
/// does not cover the other files beside it, which the model may read or run only under its sandbox.
enum ProjectSkillTrust {
    /// The project's skills, all harnesses, trusted or not.
    static func skills(named names: [String]) -> (skills: [Skill], missing: [String]) {
        let trust = SkillBook.trust()
        let catalog = SkillDiscovery.discover(
            workingDirectory: FileManager.default.currentDirectoryPath, home: NSHomeDirectory(),
            sources: SkillSource.standard, selection: SkillSelection(tokens: ["project"], knownSources: []),
            trust: trust)
        let all = catalog.skills.filter { $0.scope == .project } + catalog.untrusted.map(\.skill)
        guard !names.isEmpty else { return (all, []) }
        let wanted = Set(names.map { $0.lowercased() })
        let found = all.filter { wanted.contains($0.name.lowercased()) }
        let present = Set(found.map { $0.name.lowercased() })
        return (found, names.filter { !present.contains($0.lowercased()) })
    }

    /// Changes the store for `skills`.
    /// - Parameters:
    ///   - skills: the skills to trust or forget.
    ///   - granting: true to trust the skills as they are now, false to forget them.
    ///   - path: the trust store.
    /// - Throws: ``ConfigurationError`` when the store cannot be read or written.
    static func apply(_ skills: [Skill], granting: Bool, store path: String) throws(ConfigurationError) {
        var trust = try ProjectTrust.load(path)
        for skill in skills {
            if granting { trust.trust(skill.realFile, digest: skill.digest) } else { trust.untrust(skill.realFile) }
        }
        try trust.save(to: path)
    }
}
