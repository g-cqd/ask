// @dl:accept -- every configuration section is decoded, layered and compared by the same idiom; the keys are the data
extension ConfigurationFile {
    /// A project's file may turn subagents off, never on, nor let them write; turns within range.
    static func validateAgents(_ section: AgentsSection?, path: String, isProject: Bool) throws(ConfigurationError) {
        guard let section else { return }
        if isProject, section.enabled == true {
            throw .outOfRange(
                path: path,
                key: "agents.enabled",
                reason: "lets the model start subagents: only your own config file can turn that on"
            )
        }
        if isProject, section.allowWrites == true {
            throw .outOfRange(
                path: path,
                key: "agents.allowWrites",
                reason: "lets subagents change files: only your own config file can allow that"
            )
        }
        if isProject, section.otherHarnesses == true {
            throw .outOfRange(
                path: path,
                key: "agents.otherHarnesses",
                reason: "reads other tools' agent definitions: only your own config file can turn that on"
            )
        }
        if isProject, section.resolveWithModel == true {
            throw .outOfRange(
                path: path,
                key: "agents.resolveWithModel",
                reason:
                    "spends requests on your connection: a project's file may turn it off, only yours can turn it on"
            )
        }
        if let turns = section.maxTurns, !(1 ... AgentsSection.mostTurns).contains(turns) {
            throw .outOfRange(
                path: path,
                key: "agents.maxTurns",
                reason: "must be from 1 to \(AgentsSection.mostTurns)"
            )
        }
    }
}
