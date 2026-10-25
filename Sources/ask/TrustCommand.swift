// @dl:accept -- `ask trust` and `ask untrust` are two one-screen commands over ProjectTrust; what they share is the ParsableCommand shape
internal import ArgumentParser
internal import AskAgentCore
internal import Foundation

/// `ask trust`: let this project's `.ask/config.json` apply, as it is now.
// @dl:accept -- the two commands share the ParsableCommand shape and the isatty-free store handling; each is one screen
struct TrustCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "trust",
        abstract: "Trust this project's .ask/config.json, as it is now. A later change untrusts it again.")

    @Flag(
        name: .customLong("skills"), help: "Trust this project's skills, as they are now, instead of its configuration."
    )
    var skills = false

    @Argument(help: "With --skills: only these skills, by name. Default: every project skill.")
    var names: [String] = []

    func run() {
        // A project's file is text from a repository, and the agent has a bash tool: a prompt-injected README
        // could tell it to run this. The agent's bash has no terminal, a person does. This is a speed bump, not
        // a wall (a pty can be allocated); denying the trust store's path to the agent is the sandbox's job.
        guard isatty(STDIN_FILENO) != 0 else {
            fail("ask: trust is for a person at a terminal; it will not run from a script or a tool.", code: 77)
        }
        let loader = ConfigurationSource.here.loader
        if skills { return trustSkills(store: loader.trustPath) }
        guard names.isEmpty else { fail("ask: names are for --skills.", code: 64) }
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

    /// `ask trust --skills`: shows what is being trusted, so the person sees the words, then trusts it.
    private func trustSkills(store path: String) {
        let found = ProjectSkillTrust.skills(named: names)
        for name in found.missing {
            FileHandle.standardError.write(Data("ask: no project skill called \(name).\n".utf8))
        }
        guard !found.skills.isEmpty else { fail("ask: there are no project skills to trust.", code: 66) }
        do { try ProjectSkillTrust.apply(found.skills, granting: true, store: path) } catch {
            fail("ask: \(error)", code: 73)
        }
        for skill in found.skills {
            print("Trusted \(skill.name) (\(skill.source)): \(skill.file) (sha256 \(skill.digest.prefix(12))…)")
            print("    \(skill.description.prefix(100))")
        }
        print(
            "This trusts each SKILL.md as it is now. Other files beside it are not covered; a change to the file untrusts it."
        )
        if !found.missing.isEmpty { Foundation.exit(66) }
    }
}
