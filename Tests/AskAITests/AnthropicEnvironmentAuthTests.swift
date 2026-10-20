internal import Foundation
internal import Testing

@testable import AskAI

/// Which credential the environment supplies, and that nothing but a plain token is ever sent as one.
struct AnthropicEnvironmentAuthTests {
    private func resolve(_ environment: [String: String]) throws -> AnthropicClient.Auth? {
        try AnthropicEnvironmentAuth.resolve(environment: environment)
    }

    @Test func `nothing set is nothing, and only an API key is the key header`() throws {
        let none = try resolve([:])
        #expect(none == nil)
        let key = try resolve(["ANTHROPIC_API_KEY": "sk-ant-api-1"])
        #expect(key == .apiKey("sk-ant-api-1"))
    }

    @Test func `each variable means what pi says: the auth token is a bearer, the oauth token a subscription`() throws {
        let bearer = try resolve(["ANTHROPIC_AUTH_TOKEN": "gateway-token"])
        #expect(bearer == .bearer("gateway-token"))
        let subscription = try resolve(["ANTHROPIC_OAUTH_TOKEN": "sk-ant-oat-1"])
        #expect(subscription == .subscription(accessToken: "sk-ant-oat-1"))
    }

    @Test func `the order is auth token, then oauth token, then api key`() throws {
        let all = ["ANTHROPIC_AUTH_TOKEN": "a", "ANTHROPIC_OAUTH_TOKEN": "o", "ANTHROPIC_API_KEY": "k"]
        let first = try resolve(all)
        #expect(first == .bearer("a"))
        let second = try resolve(["ANTHROPIC_OAUTH_TOKEN": "o", "ANTHROPIC_API_KEY": "k"])
        #expect(second == .subscription(accessToken: "o"))
        let third = try resolve(["ANTHROPIC_API_KEY": "k"])
        #expect(third == .apiKey("k"))
    }

    @Test func `an empty variable is unset, so it cannot mask a valid one below it`() throws {
        let value = try resolve(["ANTHROPIC_AUTH_TOKEN": "", "ANTHROPIC_OAUTH_TOKEN": "", "ANTHROPIC_API_KEY": "k"])
        #expect(value == .apiKey("k"))
        let allEmpty = try resolve(["ANTHROPIC_AUTH_TOKEN": "", "ANTHROPIC_API_KEY": ""])
        #expect(allEmpty == nil)
    }

    @Test(arguments: [
        "has space", " lead", "trail ", "line\nbreak", "carriage\rreturn", "tab\there", "nul\u{0}byte",
        "del\u{7F}", "é", "ｔｏｋｅｎ", "a\u{200B}b"
    ])
    func `a value that is not a plain token is refused, and the message never contains it`(_ token: String) {
        for variable in ["ANTHROPIC_AUTH_TOKEN", "ANTHROPIC_OAUTH_TOKEN", "ANTHROPIC_API_KEY"] {
            do {
                _ = try AnthropicEnvironmentAuth.resolve(environment: [variable: token])
                Issue.record("\(variable) accepted \(token.debugDescription)")
            } catch {
                #expect(error == .notAToken(variable: variable))
                #expect(!error.description.contains(token), "the message must not echo the value")
                #expect(error.description.contains(variable))
            }
        }
    }

    @Test func `a token is bounded in length`() {
        let limit = AnthropicEnvironmentAuth.lengthLimit
        #expect(throws: Never.self) {
            try AnthropicEnvironmentAuth.resolve(environment: [
                "ANTHROPIC_API_KEY": String(repeating: "a", count: limit)
            ])
        }
        #expect(throws: AnthropicEnvironmentAuthError.notAToken(variable: "ANTHROPIC_API_KEY")) {
            try AnthropicEnvironmentAuth.resolve(environment: [
                "ANTHROPIC_API_KEY": String(repeating: "a", count: limit + 1)
            ])
        }
    }

    @Test func `a bad higher variable refuses the run instead of quietly using a lower credential`() {
        #expect(throws: AnthropicEnvironmentAuthError.notAToken(variable: "ANTHROPIC_AUTH_TOKEN")) {
            try AnthropicEnvironmentAuth.resolve(environment: [
                "ANTHROPIC_AUTH_TOKEN": "bad token", "ANTHROPIC_API_KEY": "good"
            ])
        }
        #expect(throws: AnthropicEnvironmentAuthError.notAToken(variable: "ANTHROPIC_OAUTH_TOKEN")) {
            try AnthropicEnvironmentAuth.resolve(environment: [
                "ANTHROPIC_OAUTH_TOKEN": "bad\ntoken", "ANTHROPIC_API_KEY": "good"
            ])
        }
    }

    @Test func `a bad lower variable is not looked at when a higher one decides`() throws {
        let value = try resolve(["ANTHROPIC_AUTH_TOKEN": "good", "ANTHROPIC_API_KEY": "bad key"])
        #expect(value == .bearer("good"))
    }
}
