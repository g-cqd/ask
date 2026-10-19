internal import ArgumentParser
internal import AskAgentCore
internal import Foundation

/// `ask untrust`: stop applying this project's `.ask/config.json`.
struct UntrustCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "untrust", abstract: "Stop trusting this project's .ask/config.json.")

    func run() {
        let loader = ConfigurationSource.here.loader
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
