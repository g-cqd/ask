import Testing

@testable import AskAgentCore

/// Well-known credential variables are kept from commands by default (owner, 2026-10-31, roadmap 0153): a token a command prints goes to
/// the model and on to its provider. `environment.pass` lets one back in, for a person whose `gh` or `aws` should work as they are.
@Suite("Well-known credentials are withheld from commands unless passed")
struct WellKnownCredentialTests {
    private func policy(_ configured: EnvironmentSection = EnvironmentSection()) -> CommandEnvironment {
        CommandEnvironment(credentials: [], credentialPrefixes: [], configured: configured)
    }

    @Test(arguments: [
        "GITHUB_TOKEN", "GH_TOKEN", "AWS_SECRET_ACCESS_KEY", "AWS_SESSION_TOKEN", "OPENAI_API_KEY", "NPM_TOKEN",
        "GITLAB_TOKEN", "HF_TOKEN", "CLOUDFLARE_API_TOKEN"
    ])
    func `a well-known credential is withheld`(name: String) {
        #expect(policy().withholds(name))
    }

    @Test func `ordinary variables are still inherited`() {
        for name in [
            "PATH", "HOME", "GITHUB_ACTIONS", "NPM_CONFIG_PREFIX", "TOKENIZERS_PARALLELISM", "MY_SERVICE_TOKEN"
        ] {
            #expect(!policy().withholds(name), "\(name)")
        }
    }

    @Test func `pass lets one back in`() {
        let passed = policy(EnvironmentSection(pass: ["GITHUB_TOKEN"]))
        #expect(!passed.withholds("GITHUB_TOKEN") && passed.withholds("GH_TOKEN"))
    }

    @Test func `the library's inherit policy withholds nothing`() {
        #expect(!CommandEnvironment.inherit.withholds("GITHUB_TOKEN"))
    }
}
