// @dl:accept -- the commands share a shape
internal import ArgumentParser
internal import AskAgentCore
internal import Foundation

/// `ask untrust`: stop applying this project's `.ask/config.json`.
// @dl:accept -- the two commands share the ParsableCommand shape; each is one screen
struct UntrustCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "untrust", abstract: "Stop trusting this project's .ask/config.json.")

    @Flag(name: .customLong("skills"), help: "Stop trusting this project's skills instead of its configuration.")
    var skills = false

    @Argument(help: "With --skills: only these skills, by name. Default: every project skill.")
    var names: [String] = []

    func run() {
        let loader = ConfigurationSource.here.loader
        if skills {
            let found = ProjectSkillTrust.skills(named: names)
            do { try ProjectSkillTrust.apply(found.skills, granting: false, store: loader.trustPath) } catch {
                fail("ask: \(error)", code: 73)
            }
            for skill in found.skills { print("No longer trusting \(skill.name): \(skill.file)") }
            for name in found.missing { print("No project skill called \(name).") }
            return
        }
        guard names.isEmpty else { fail("ask: names are for --skills.", code: 64) }
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
