// @dl:accept -- `ask trust` and `ask untrust` are two one-screen commands over ProjectTrust; what they share is the ParsableCommand shape
internal import ArgumentParser
internal import AskAgentCore
internal import Foundation

/// `ask trust`: let this project's `.ask/config.json` apply, as it is now.
struct TrustCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "trust",
        abstract: "Trust this project's .ask/config.json, as it is now. A later change untrusts it again.")

    func run() {
        let loader = ConfigurationSource.here.loader
        guard let data = FileManager.default.contents(atPath: loader.projectPath) else {
            fail("ask: there is no \(loader.projectPath).", code: 66)
        }
        let bytes = [UInt8](data)
        let file: ConfigurationFile
        do { file = try ConfigurationFile.parse(bytes, path: loader.projectPath) } catch {
            fail("ask: not trusting a file that does not load: \(error)", code: 78)
        }
        do {
            var trust = try ProjectTrust.load(loader.trustPath)
            trust.trust(loader.projectPath, bytes: bytes)
            try trust.save(to: loader.trustPath)
        } catch {
            fail("ask: \(error)", code: 73)
        }
        let sets = ConfigurationFile.keys.filter { file.sets($0) }
        print("Trusted \(loader.projectPath) (sha256 \(ProjectTrust.digest(bytes).prefix(12))…).")
        print(sets.isEmpty ? "It sets nothing." : "It sets: " + sets.joined(separator: ", ") + ".")
    }
}
