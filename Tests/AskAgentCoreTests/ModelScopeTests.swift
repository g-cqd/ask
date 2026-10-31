import Testing

@testable import AskAgentCore

/// `modelScopes` (roadmap 0094): the person's own file limits which providers serve a repository, by where it is, its git remote or
/// the git identity it commits as. The first rule that matches decides; no rule matching means no limit.
@Suite("Model scopes limit the providers of a repository")
struct ModelScopeTests {
    private func parse(_ json: String, project: Bool = false) throws -> ConfigurationFile {
        try ConfigurationFile.parse(Array(json.utf8), path: "c.json", isProject: project)
    }

    private func facts(
        _ project: String = "/Users/me/work/app", remotes: [String] = [], identities: [String] = []
    ) -> RepositoryFacts {
        RepositoryFacts(project: project, home: "/Users/me", remotes: remotes, identities: identities)
    }

    private let work = ModelScope(path: "~/work", providers: ["codex", "work"])

    @Test func `the rules are read from your own file, in order, and a reload names the change`() throws {
        let file = try parse(
            #"{"modelScopes": [{"path": "~/work", "providers": ["codex", "work"]}, {"remote": "*acme/*", "identity": "*@acme.com", "providers": ["anthropic"]}]}"#
        )
        #expect(
            file.modelScopes == [
                work, ModelScope(remote: "*acme/*", identity: "*@acme.com", providers: ["anthropic"])
            ])
        #expect(file.sets("modelScopes"))
        let configured = Configuration.defaults.applying(file, from: .file("/u/config.json"))
        #expect(configured.modelScopes.value.count == 2)
        #expect(configured.changes(from: .defaults).first?.hasPrefix("modelScopes: ") == true)
    }

    @Test func `a project's file may not hold them`() {
        #expect(throws: ConfigurationError.self) {
            try parse(#"{"modelScopes": [{"path": "~/work", "providers": ["codex"]}]}"#, project: true)
        }
    }

    @Test func `a rule without a matcher, without providers, or with an unknown key is refused`() {
        for json in [
            #"{"modelScopes": [{"providers": ["codex"]}]}"#, #"{"modelScopes": [{"path": "~/w", "providers": []}]}"#,
            #"{"modelScopes": [{"path": "~/w"}]}"#,
            #"{"modelScopes": [{"path": "~/w", "providers": ["c"], "branch": "x"}]}"#,
            #"{"modelScopes": [{"path": "", "providers": ["c"]}]}"#, #"{"modelScopes": {"path": "~/w"}}"#
        ] {
            #expect(throws: (any Error).self, "\(json)") { try parse(json) }
        }
    }

    @Test func `a path matches its folder and everything beneath, not a sibling that starts the same`() {
        #expect(work.matches(facts("/Users/me/work")))
        #expect(work.matches(facts("/Users/me/work/app/sub")))
        #expect(!work.matches(facts("/Users/me/workshop")))
        #expect(ModelScope(path: "/Users/ME/Work", providers: ["c"]).matches(facts("/Users/me/work/app")))
        let clients = ModelScope(path: "~/clients/*/app", providers: ["c"])
        #expect(clients.matches(facts("/Users/me/clients/acme/app/src")))
        #expect(!clients.matches(facts("/Users/me/clients/acme/web")))
    }

    @Test func `a remote matches any of the repository's remotes, and an identity its address or its name`() {
        let acme = ModelScope(remote: "*github.com?acme/*", providers: ["c"])
        #expect(acme.matches(facts(remotes: ["https://example.com/x", "git@GitHub.com:Acme/tool.git"])))
        #expect(acme.matches(facts(remotes: ["https://github.com/acme/tool"])))
        #expect(!acme.matches(facts(remotes: ["https://github.com/other/tool"])))
        #expect(!acme.matches(facts()))
        let me = ModelScope(identity: "*@acme.com", providers: ["c"])
        #expect(me.matches(facts(identities: ["Jane Doe", "jane@ACME.com"])))
        #expect(!me.matches(facts(identities: ["jane@home.example"])))
        #expect(ModelScope(identity: "Jane Doe", providers: ["c"]).matches(facts(identities: ["jane doe"])))
    }

    @Test func `every matcher a rule names must match`() {
        let both = ModelScope(path: "~/work", identity: "*@acme.com", providers: ["c"])
        #expect(both.matches(facts(identities: ["jane@acme.com"])))
        #expect(!both.matches(facts(identities: ["jane@home.example"])))
        #expect(!both.matches(facts("/tmp/x", identities: ["jane@acme.com"])))
    }

    @Test func `the first rule that matches decides, and none matching is no limit`() {
        var configuration = Configuration.defaults
        configuration.modelScopes = Configuration.Setting(
            value: [ModelScope(path: "~/other", providers: ["x"]), work, ModelScope(path: "~", providers: ["y"])],
            source: .file("/u/config.json"))
        let match = configuration.modelScope(for: facts())
        #expect(match?.number == 2)
        #expect(match?.allows("work") == true && match?.allows("Codex") == true)
        #expect(match?.allows("anthropic") == false)
        #expect(configuration.modelScope(for: facts("/tmp/elsewhere")) == nil)
        #expect(Configuration.defaults.modelScope(for: facts()) == nil)
    }

    @Test
    func `a provider you named outside the rule is refused; one ask or a file chose is replaced by the rule's first`() {
        let match = ModelScopeMatch(number: 2, scope: work)
        #expect(match.verdict(on: "WORK", named: true) == .allowed)
        #expect(match.verdict(on: "anthropic", named: true) == .refused(match.refusal(of: "anthropic")))
        #expect(
            match.verdict(on: "anthropic", named: false)
                == .replaced(
                    by: "codex", "modelScopes rule 2 (path ~/work) does not allow anthropic here: using codex."))
    }

    @Test func `a refusal names the provider, the rule and what it allows`() {
        let match = ModelScopeMatch(number: 2, scope: work)
        #expect(
            match.refusal(of: "anthropic")
                == "anthropic is not allowed here: modelScopes rule 2 (path ~/work) allows only codex, work. "
                + "Choose one of them with --provider or /model.")
    }
}
