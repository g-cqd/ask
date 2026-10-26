import Testing

@testable import AskAgentCore

/// ask's own instructions, the first thing the model reads (ADR-0007): where it works, what it does with commands, and what the sandbox
/// allows. The text is the same bytes for the same inputs, so the provider's prompt cache is not broken between requests.
@Suite("The model's instructions say where it works and what it is allowed")
struct SystemInstructionsTests {
    @Test func `the working directory is named`() {
        let text = SystemInstructions.text(workingDirectory: "/work/project", sandbox: .unrestricted)
        #expect(text.contains("The working directory is /work/project."))
    }

    @Test func `the instructions say how to run long commands as jobs`() {
        let text = SystemInstructions.text(workingDirectory: "/w", sandbox: .unrestricted)
        for word in ["yield_seconds", "wait", "job_input", "job_stop"] { #expect(text.contains(word), "\(word)") }
    }

    @Test func `an unrestricted run adds no sandbox sentence`() {
        let text = SystemInstructions.text(workingDirectory: "/w", sandbox: .unrestricted)
        #expect(text.hasSuffix("say plainly what you did not verify."))
    }

    @Test func `a restricted run ends with what its sandbox allows`() throws {
        let policy = SandboxPolicy(network: .none)
        let rules = try #require(policy.summary)
        let text = SystemInstructions.text(workingDirectory: "/w", sandbox: policy)
        #expect(text.hasSuffix(" " + rules))
    }

    @Test func `the same inputs give the same bytes`() {
        let policy = SandboxPolicy(network: .localhost)
        #expect(
            SystemInstructions.text(workingDirectory: "/w", sandbox: policy)
                == SystemInstructions.text(workingDirectory: "/w", sandbox: policy))
    }

    @Test func `a different directory changes the text`() {
        #expect(
            SystemInstructions.text(workingDirectory: "/a", sandbox: .unrestricted)
                != SystemInstructions.text(workingDirectory: "/b", sandbox: .unrestricted))
    }
}
