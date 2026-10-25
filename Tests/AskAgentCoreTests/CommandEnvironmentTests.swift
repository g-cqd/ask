import Testing

@testable import AskAgentCore

@Suite("A command inherits ask's environment except what ask itself reads credentials from")
struct CommandEnvironmentTests {
    private static let environment = [
        "ANTHROPIC_API_KEY": "k", "ANTHROPIC_BASE_URL": "u", "OPENROUTER_API_KEY": "o", "ASK_MODEL": "m",
        "PATH": "/bin",
        "HOME": "/h", "MY_SERVICE_TOKEN": "t", "XANTHROPIC_KEY": "x", "anthropic_api_key": "lower", "EMPTY": ""
    ]

    private func policy(
        _ configured: EnvironmentSection = EnvironmentSection(),
        credentials: Set<String> = ["ANTHROPIC_API_KEY", "OPENROUTER_API_KEY"],
        prefixes: [String] = ["ANTHROPIC_", "ASK_"]
    ) -> CommandEnvironment {
        CommandEnvironment(credentials: credentials, credentialPrefixes: prefixes, configured: configured)
    }

    @Test func `with no policy every variable is inherited, untouched`() {
        #expect(CommandEnvironment.inherit.filtered(Self.environment) == Self.environment)
        #expect(!CommandEnvironment.inherit.withholds("ANTHROPIC_API_KEY"))
    }

    @Test func `the variables ask reads credentials from are withheld, and nothing else is`() {
        let kept = policy().filtered(Self.environment)
        #expect(kept["ANTHROPIC_API_KEY"] == nil && kept["OPENROUTER_API_KEY"] == nil)
        #expect(kept["PATH"] == "/bin" && kept["HOME"] == "/h" && kept["MY_SERVICE_TOKEN"] == "t")
    }

    @Test func `a prefix withholds what starts with it, and only that`() {
        let kept = policy().filtered(Self.environment)
        #expect(kept["ANTHROPIC_BASE_URL"] == nil && kept["ASK_MODEL"] == nil)
        #expect(kept["XANTHROPIC_KEY"] == "x", "the prefix is at the start of the name")
    }

    @Test func `names are matched as written, because the environment is case-sensitive`() {
        #expect(policy().filtered(Self.environment)["anthropic_api_key"] == "lower")
    }

    @Test func `a value that stays is exactly as it was, even an empty one`() {
        let kept = policy().filtered(Self.environment)
        #expect(kept["EMPTY"] == "" && kept.count == 6)
    }

    @Test func `a withheld variable is withheld whatever its value, including an empty one`() {
        #expect(policy().filtered(["ANTHROPIC_API_KEY": ""]).isEmpty)
    }

    @Test func `a configured name is withheld too, exactly or by prefix`() {
        let kept = policy(EnvironmentSection(withhold: ["MY_SERVICE_TOKEN", "AWS_*"]))
            .filtered(
                Self.environment.merging(["AWS_PROFILE": "p", "AWS_SECRET_ACCESS_KEY": "s", "AWSOME": "a"]) { $1 })
        #expect(kept["MY_SERVICE_TOKEN"] == nil && kept["AWS_PROFILE"] == nil && kept["AWS_SECRET_ACCESS_KEY"] == nil)
        #expect(kept["AWSOME"] == "a", "`AWS_*` is a prefix of `AWS_`, not of `AWS`")
    }

    @Test func `a configured pass lets a withheld credential through, exactly`() {
        let kept = policy(EnvironmentSection(pass: ["ANTHROPIC_API_KEY", "ASK_MODEL"])).filtered(Self.environment)
        #expect(kept["ANTHROPIC_API_KEY"] == "k" && kept["ASK_MODEL"] == "m")
        #expect(kept["ANTHROPIC_BASE_URL"] == nil && kept["OPENROUTER_API_KEY"] == nil, "only the names passed")
    }

    @Test
    func `a name the configuration both passes and withholds is withheld, so a project can narrow what a user passed`()
    {
        let section = EnvironmentSection(
            pass: ["MY_SERVICE_TOKEN", "AWS_PROFILE"], withhold: ["MY_SERVICE_TOKEN", "AWS_*"])
        let kept = policy(section).filtered(Self.environment.merging(["AWS_PROFILE": "p"]) { $1 })
        #expect(kept["MY_SERVICE_TOKEN"] == nil && kept["AWS_PROFILE"] == nil)
    }

    @Test func `withholds agrees with filtered for every name`() {
        let policy = policy(EnvironmentSection(withhold: ["MY_SERVICE_TOKEN"]))
        for name in Self.environment.keys {
            #expect(policy.withholds(name) == (policy.filtered([name: "v"])[name] == nil), "\(name)")
        }
    }

    @Test func `filtering an empty environment is empty`() {
        #expect(policy().filtered([:]).isEmpty)
    }

    @Test func `two tool contexts that differ only in what commands may inherit are not the same context`() {
        let open = ToolContext(workingDirectory: "/w")
        let closed = ToolContext(workingDirectory: "/w", commandEnvironment: CommandEnvironment(withheld: ["X"]))
        #expect(open != closed)
        #expect(closed == ToolContext(workingDirectory: "/w", commandEnvironment: CommandEnvironment(withheld: ["X"])))
        #expect(open.commandEnvironment == .inherit)
    }
}
