internal import Testing

@testable import AskAI

/// `ask login` and `/login` read the same words (ADR-0117), so neither offers a way the other lacks.
@Suite("Login words name one sign-in, and the wrong ones are refused with a reason")
struct LoginRequestTests {
    private func request(_ words: String) throws -> LoginRequest {
        try LoginRequest(words: words.split(separator: " ").map(String.init))
    }

    @Test func `no words is Claude's account, as ask login always was`() throws {
        let request = try LoginRequest(words: [])
        #expect(request.target == "claude" && request.method == nil && !request.usesTypedKey)
    }

    @Test func `anthropic is Claude`() throws { #expect(try request("anthropic").target == "claude") }

    @Test(arguments: ["claude api-key", "claude --api-key"])
    func `an API key is a typed key stored under anthropic`(words: String) throws {
        let request = try request(words)
        #expect(request.usesTypedKey && request.keyProvider == "anthropic")
    }

    @Test func `Codex's API key is OpenAI's, stored as openai`() throws {
        let request = try request("codex api-key")
        #expect(request.usesTypedKey && request.keyProvider == "openai")
        #expect(try !self.request("codex").usesTypedKey && self.request("codex device").method == .device)
    }

    @Test func `any provider with a key preset signs in with its key`() throws {
        let request = try request("groq")
        #expect(request.usesTypedKey && request.keyProvider == "groq")
    }

    @Test func `the browser sign-ins that issue a key are not typed keys`() throws {
        for name in ["spettro", "mistral-vibe", "agy"] { #expect(try !request(name).usesTypedKey, "\(name)") }
    }

    @Test func `a custom endpoint takes a name and an address`() throws {
        let request = try request("custom my-llm http://localhost:8181/v1")
        #expect(request.endpointName == "my-llm" && request.endpointURL == "http://localhost:8181/v1")
        #expect(request.usesTypedKey && request.keyProvider == "my-llm")
    }

    @Test func `a named connection is for an account, never a key`() throws {
        #expect(try request("codex --name work").connection == "work")
        #expect(throws: LoginRequest.Invalid.self) { try request("codex api-key --name work") }
        #expect(throws: LoginRequest.Invalid.self) { try request("groq --name work") }
    }

    @Test(arguments: ["nonsense", "claude device", "agy api-key", "claude extra", "custom a b c", "claude --name"])
    func `wrong words are refused`(words: String) {
        #expect(throws: LoginRequest.Invalid.self) { try request(words) }
    }

    @Test func `replacing an account is a flag`() throws {
        #expect(try request("codex --name work --replace-account").replaceAccount)
    }
}
