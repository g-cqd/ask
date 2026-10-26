import Testing

@testable import AskAgentCore

/// ask's own instructions, the first thing the model reads (ADR-0007): where it works and what it does with commands. The sandbox is not in them (ADR-0115).
@Suite("The model's instructions say where it works and nothing of the sandbox")
struct SystemInstructionsTests {
    @Test func `the working directory is named`() {
        let text = SystemInstructions.text(workingDirectory: "/work/project")
        #expect(text.contains("The working directory is /work/project."))
    }

    @Test func `the instructions say how to run long commands as jobs`() {
        let text = SystemInstructions.text(workingDirectory: "/w")
        for word in ["yield_seconds", "wait", "job_input", "job_stop"] { #expect(text.contains(word), "\(word)") }
    }

    @Test func `the instructions say nothing about the sandbox, however the run is restricted`() {
        let text = SystemInstructions.text(workingDirectory: "/w")
        for word in ["andbox", "protected", "network", "Only the user", "disable-sandbox", "allowRead"] {
            #expect(!text.contains(word), "\(word)")
        }
    }

    @Test func `the same input gives the same bytes`() {
        #expect(SystemInstructions.text(workingDirectory: "/w") == SystemInstructions.text(workingDirectory: "/w"))
    }

    @Test func `a different directory changes the text`() {
        #expect(
            SystemInstructions.text(workingDirectory: "/a")
                != SystemInstructions.text(workingDirectory: "/b"))
    }
}
