internal import Foundation
internal import Testing

@testable import AskAI

/// `ANTHROPIC_BASE_URL` may move where requests go, but never where a credential travels in the clear.
///
/// Every request carries a bearer credential: an API key or a subscription's OAuth token. The variable is
/// process-wide and often set by a tool or a shell profile the user did not read, so a plain `http://` URL to
/// another machine would send the credential in the clear to whoever answers. Plain HTTP stays available to
/// this machine, which is what a local gateway or a test server needs.
@Suite("The configured endpoint never sends a credential in the clear to another machine")
struct AnthropicEndpointTests {
    private static let official = "https://api.anthropic.com/v1/messages"

    private func endpoint(_ base: String) -> String {
        AnthropicClient.endpoint(environment: ["ANTHROPIC_BASE_URL": base]).absoluteString
    }

    @Test(arguments: ["http://localhost:8080", "http://127.0.0.1:8080", "http://[::1]:8080"])
    func `plain http is accepted for this machine`(base: String) {
        #expect(endpoint(base) == base + "/v1/messages")
        #expect(AnthropicClient.endpointProblem(environment: ["ANTHROPIC_BASE_URL": base]) == nil)
    }

    @Test func `https is accepted for any host`() {
        #expect(endpoint("https://gw.example/anthropic") == "https://gw.example/anthropic/v1/messages")
    }

    @Test(arguments: [
        "http://gw.example", "http://10.0.0.5:8080", "http://localhost.evil.example", "ftp://gw.example", "file:///etc"
    ])
    func `plain http to another machine, and other schemes, are refused`(base: String) {
        #expect(endpoint(base) == Self.official)
        #expect(AnthropicClient.endpointProblem(environment: ["ANTHROPIC_BASE_URL": base]) != nil)
    }

    @Test func `a value that is not a URL is reported, not silently ignored`() {
        #expect(endpoint("not a url") == Self.official)
        #expect(AnthropicClient.endpointProblem(environment: ["ANTHROPIC_BASE_URL": "not a url"]) != nil)
    }

    @Test func `an unset or empty variable is not a problem`() {
        #expect(AnthropicClient.endpointProblem(environment: [:]) == nil)
        #expect(AnthropicClient.endpointProblem(environment: ["ANTHROPIC_BASE_URL": ""]) == nil)
    }

    @Test func `the explanation names the variable and does not echo its value`() throws {
        let value = "http://user:secret-token@gw.example"
        let problem = try #require(AnthropicClient.endpointProblem(environment: ["ANTHROPIC_BASE_URL": value]))
        #expect(problem.contains("ANTHROPIC_BASE_URL"))
        #expect(!problem.contains("secret-token"))
    }
}
