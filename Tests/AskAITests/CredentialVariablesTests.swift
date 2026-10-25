internal import Testing

@testable import AskAI

/// The variables ask itself reads credentials from: what a command the model runs must not inherit (ADR-0106).
struct CredentialVariablesTests {
    private func settings(_ json: String) throws -> ProviderSettings {
        try ProviderSettings(decoding: Array(json.utf8))
    }

    @Test func `the Anthropic variables are the ones the environment sign-in reads, from one list`() {
        #expect(
            Set(AnthropicEnvironmentAuth.variables) == [
                "ANTHROPIC_AUTH_TOKEN", "ANTHROPIC_OAUTH_TOKEN", "ANTHROPIC_API_KEY"
            ])
        for name in AnthropicEnvironmentAuth.variables {
            #expect(throws: Never.self) { _ = try AnthropicEnvironmentAuth.resolve(environment: [name: "x"]) }
            #expect((try? AnthropicEnvironmentAuth.resolve(environment: [name: "x"])) != nil, "\(name) is read")
        }
        #expect(CredentialVariables.names(settings: .none).isSuperset(of: AnthropicEnvironmentAuth.variables))
    }

    @Test func `every preset's key variable is named`() {
        let names = CredentialVariables.names(settings: .none)
        #expect(names.contains("BASETEN_API_KEY") && names.contains("CEREBRAS_API_KEY"))
        #expect(ProviderPreset.all.compactMap(\.keyVariable).allSatisfy(names.contains))
    }

    @Test
    func
        `a variable providers.json names for a key is named, in either spelling, and a literal key or an escape is not`()
        throws
    {
        let json = #"""
            { "providers": {
              "a": { "api": "openai-completions", "baseUrl": "http://127.0.0.1:1/v1", "apiKey": "${GW_KEY}" },
              "b": { "api": "openai-completions", "baseUrl": "http://127.0.0.1:2/v1", "apiKey": "$OTHER_KEY" },
              "c": { "api": "openai-completions", "baseUrl": "http://127.0.0.1:3/v1", "apiKey": "sk-literal-123" },
              "d": { "api": "openai-completions", "baseUrl": "http://127.0.0.1:4/v1", "apiKey": "$$NOT_A_NAME" },
              "e": { "api": "openai-completions", "baseUrl": "http://127.0.0.1:5/v1" },
              "f": { "api": "openai-completions", "baseUrl": "http://127.0.0.1:6/v1", "apiKey": "$" } } }
            """#
        let names = CredentialVariables.names(settings: try settings(json))
        #expect(names.contains("GW_KEY") && names.contains("OTHER_KEY"))
        #expect(!names.contains("sk-literal-123") && !names.contains("NOT_A_NAME") && !names.contains("$NOT_A_NAME"))
        #expect(!names.contains(""))
    }

    @Test func `a prefix covers the rest of ask's own namespace`() {
        #expect(CredentialVariables.prefixes == ["ANTHROPIC_", "ASK_"])
    }

    @Test func `the name in a key is read the way interpolation reads it`() {
        #expect(
            ProviderSettings.variableName(in: "$KEY") == "KEY" && ProviderSettings.variableName(in: "${KEY}") == "KEY")
        #expect(ProviderSettings.variableName(in: "$$KEY") == nil && ProviderSettings.variableName(in: "KEY") == nil)
        #expect(ProviderSettings.variableName(in: "$") == "", "an empty name is the caller's to drop")
    }
}
