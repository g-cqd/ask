import Foundation
import Testing

@testable import AskAI

/// Where each provider's requests go, for the `provider` network level's allow list (roadmap 0021).
@Suite("Each provider's endpoint")
struct ProviderServerTests {
    @Test func `the built-in providers' servers, and a configured provider's base URL`() {
        let url = { (provider: ResolvedModel.Provider) in
            ProviderServer.url(for: ResolvedModel(provider: provider, model: "m"), environment: [:])?.host()
        }
        #expect(url(.anthropic) == "api.anthropic.com")
        #expect(url(.codex) == "chatgpt.com")
        #expect(url(.copilot) == "api.githubcopilot.com")
        #expect(url(.agy) == "daily-cloudcode-pa.googleapis.com")
        #expect(url(.apple) == nil, "on the device: no server")
        let base = URL(string: "https://llm.example.test:8443/v1")!
        #expect(url(.openAICompatible(name: "x", baseURL: base, apiKey: nil, headers: [:])) == "llm.example.test")
        #expect(url(.openAIResponses(name: "x", baseURL: base, apiKey: nil, headers: [:])) == "llm.example.test")
    }

    @Test func `Anthropic's base URL from the environment is followed`() {
        let model = ResolvedModel(provider: .anthropic, model: "m")
        let url = ProviderServer.url(for: model, environment: ["ANTHROPIC_BASE_URL": "https://gateway.example.test"])
        #expect(url?.host() == "gateway.example.test")
    }
}
