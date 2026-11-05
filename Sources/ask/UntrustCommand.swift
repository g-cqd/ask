// @dl:accept -- the commands share a shape
internal import ArgumentParser
internal import AskAgentCore
internal import Foundation

/// `ask untrust`: stop applying this project's `.ask/config.json`.
// @dl:accept -- the two commands share the ParsableCommand shape; each is one screen
struct UntrustCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "untrust",
        abstract: "Stop trusting this project's .ask/config.json."
    )

    @Flag(name: .customLong("skills"), help: "Stop trusting this project's skills instead of its configuration.")
    var skills = false

    @Flag(
        name: .customLong("agents"),
        help: "Stop trusting this project's agent definitions instead of its configuration."
    )
    var agents = false

    @Argument(help: "With --skills or --agents: only these, by name. Default: every one the project has.")
    var names: [String] = []

    func run() {
        let loader = ConfigurationSource.here.loader
        if skills {
            return TrustedFile.untrust(ProjectSkillTrust.files(named: names), kind: "skill", store: loader.trustPath)
        }
        if agents {
            return TrustedFile.untrust(ProjectAgentTrust.files(named: names), kind: "agent", store: loader.trustPath)
        }
        guard names.isEmpty else { fail("ask: names are for --skills or --agents.", code: 64) }
        do {
            var trust = try ProjectTrust.load(loader.trustPath)
            guard trust.untrust(loader.projectPath) else {
                print("\(loader.projectPath) was not trusted.")
                return
            }
            try trust.save(to: loader.trustPath)
            print("No longer trusting \(loader.projectPath).")
        } catch {
            fail("ask: \(error)", code: 73)
        }
    }
}
