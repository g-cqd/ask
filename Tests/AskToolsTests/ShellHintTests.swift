import AskAI
import AskAgentCore
import Testing

@testable import AskTools

@Suite("Shell hints use only the permitted launch environment and describe syntax")
struct ShellHintTests {
    @Test func `the advertised default shell and syntax follow the injected launch environment`() {
        let tool = BashTool(jobs: JobTable(environment: ["SHELL": "/bin/sh"]))
        #expect(tool.definition.description.contains("/bin/sh"))
        #expect(tool.definition.description.contains("sh syntax"))
        // The description must say where the command goes: the on-device model read `shell` as the command and
        // retried against a refusal that never taught the shape (probed live, diary 2026-10-28).
        #expect(tool.definition.description.lowercased().contains("the command to run goes in command"))
    }

    @Test func `withheld shell variables do not leak into the model's tool description`() {
        let tool = BashTool(
            jobs: JobTable(environment: ["SHELL": "/bin/sh"]),
            commandEnvironment: CommandEnvironment(withheld: ["SHELL"]))
        #expect(tool.definition.description.contains("/bin/bash"))
        #expect(!tool.definition.description.contains("/bin/sh"))
    }

    @Test(arguments: ["/", "/nonexistent", "relative-shell"])
    func `invalid environment shell candidates fall back to an executable file`(_ shell: String) {
        let jobs = JobTable(environment: ["SHELL": shell])
        #expect(jobs.commandShell(nil, in: ToolContext(workingDirectory: "/tmp")) == "/bin/bash")
    }

    @Test func `an invalid explicit override is refused before any process is allocated`() async throws {
        let jobs = JobTable()
        let input = try JSONObject(validating: Array(#"{"command":"true","shell":"/nonexistent"}"#.utf8))
        let output = await BashTool(jobs: jobs).run(input, in: ToolContext(workingDirectory: "/tmp"))
        #expect(output.isError)
        #expect(jobs.job("job-1") == nil)
    }
}
