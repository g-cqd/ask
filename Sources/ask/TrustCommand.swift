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
        // A project's file is text from a repository, and the agent has a bash tool: a prompt-injected README
        // could tell it to run this. The agent's bash has no terminal, a person does. This is a speed bump, not
        // a wall (a pty can be allocated); denying the trust store's path to the agent is the sandbox's job.
        guard isatty(STDIN_FILENO) != 0 else {
            fail("ask: trust is for a person at a terminal; it will not run from a script or a tool.", code: 77)
        }
        let loader = ConfigurationSource.here.loader
        guard let data = FileManager.default.contents(atPath: loader.projectPath) else {
            fail("ask: there is no \(loader.projectPath).", code: 66)
        }
        let bytes = [UInt8](data)
        let file: ConfigurationFile
        do { file = try ConfigurationFile.parse(bytes, path: loader.projectPath, isProject: true) } catch {
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
        // Naming a server runs a program: say which, so that trusting the file is consent to something stated.
        if let servers = file.mcp?.consent, !servers.isEmpty {
            print("Trusting it lets this project start or connect to MCP servers, outside ask's sandbox:")
            for line in servers { print("  \(line)") }
        }
    }
}
