package import AskAgentCore
internal import AskTools
internal import Foundation

/// The skills one run offers: found when the loop is made (on the first prompt, never at launch), listed in the system prompt, and served by the
/// `skill` tool. Nothing else about a skill reaches the model.
package struct SkillBook {
    let block: String?
    let tool: SkillTool?
    let catalog: SkillCatalog
    let knownSources: [String]

    /// The skills `configuration` offers, its organisation's policy applied (``SkillOrigins``).
    init(_ configuration: Configuration, workingDirectory: String) {
        self.init(
            configuration.skills.value,
            workingDirectory: workingDirectory,
            origins: .of(configuration.policy.value)
        )
    }

    /// - Parameters:
    ///   - section: the `skills` configuration. Off means no block and no tool: the model is not told skills exist.
    ///   - workingDirectory: where the project is.
    ///   - origins: where skills may come from; under the organisation's policy, its folder alone.
    init(_ section: SkillsSection, workingDirectory: String, origins: SkillOrigins) {
        let known = origins.sources.map(\.id)
        guard section.enabled != false else {
            self.init(block: nil, tool: nil, catalog: SkillCatalog(), knownSources: known)
            return
        }
        // The user's skills, a project's, and the bundled ones for `from`. A project's skill is text from a repository: discovery loads it only when
        // the user has trusted its file as it is now (`ask trust --skills`), and sets the others aside for `ask skills` to report.
        let catalog = SkillDiscovery.discover(
            workingDirectory: workingDirectory,
            home: NSHomeDirectory(),
            sources: origins.sources,
            selection: SkillSelection(
                tokens: origins.imposed ?? ["user", "project", "bundled"] + (section.sources ?? []),
                knownSources: known
            ),
            trust: Self.trust()
        )
        let block = SkillAdvertisement.block(
            for: catalog,
            limit: section.maxAdvertised ?? SkillsSection.defaultMaxAdvertised
        )
        self.init(
            block: block,
            tool: catalog.skills.isEmpty ? nil : SkillTool(catalog: catalog, knownSources: known),
            catalog: catalog,
            knownSources: known
        )
    }

    /// What the user has trusted. A store that cannot be read trusts nothing: the project's skills are then not loaded, which is the safe way to be wrong.
    package static func trust() -> ProjectTrust {
        (try? ProjectTrust.load(ConfigurationSource.here.loader.trustPath)) ?? ProjectTrust()
    }

    private init(block: String?, tool: SkillTool?, catalog: SkillCatalog, knownSources: [String]) {
        self.block = block
        self.tool = tool
        self.catalog = catalog
        self.knownSources = knownSources
    }
}
