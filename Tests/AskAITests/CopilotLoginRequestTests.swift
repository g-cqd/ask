internal import AskAI
internal import Testing

@Suite("Copilot login request")
struct CopilotLoginRequestTests {
    @Test func `Copilot is an account sign in rather than a typed key`() throws {
        let request = try LoginRequest(words: ["copilot-vscode"])
        #expect(!request.usesTypedKey)
        #expect(request.keyProvider == nil)
    }

    @Test func `Copilot accepts an explicit device method`() throws {
        let request = try LoginRequest(words: ["copilot-vscode", "device"])
        #expect(request.method == .device)
    }
}
