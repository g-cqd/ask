internal import AskAgentCore
internal import AskTools
internal import Foundation

/// The skills one run offers: found when the loop is made (on the first prompt, never at launch), listed in the system prompt, and served by the
/// `skill` tool. Nothing else about a skill reaches the model.
struct SkillBook {
    let block: String?
    let tool: SkillTool?

    /// - Parameters:
    ///   - section: the `skills` configuration. Off means no block and no tool: the model is not told skills exist.
    ///   - workingDirectory: where the project is.
    init(_ section: SkillsSection, workingDirectory: String) {
        guard section.enabled != false else {
            self.init(block: nil, tool: nil)
            return
        }
        let known = SkillSource.standard.map(\.id)
        // The user's skills, and the bundled ones for `from`. A project's skills wait for project trust (roadmap 0061, phase 4): they are text from a
        // repository, and nothing in this run has been trusted, so a `project` in the configuration is not honoured here.
        let words = (section.sources ?? []).filter { $0.lowercased() != "project" }
        let catalog = SkillDiscovery.discover(
            workingDirectory: workingDirectory, home: NSHomeDirectory(), sources: SkillSource.standard,
            selection: SkillSelection(tokens: ["user", "bundled"] + words, knownSources: known))
        let block = SkillAdvertisement.block(
            for: catalog, limit: section.maxAdvertised ?? SkillsSection.defaultMaxAdvertised)
        self.init(
            block: block, tool: catalog.skills.isEmpty ? nil : SkillTool(catalog: catalog, knownSources: known))
    }

    private init(block: String?, tool: SkillTool?) {
        self.block = block
        self.tool = tool
    }
}
