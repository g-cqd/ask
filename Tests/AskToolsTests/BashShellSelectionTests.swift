import AskAI
import AskAgentCore
import Testing

@testable import AskTools

@Suite("Shell commands use the launch environment or an explicit override")
struct BashShellSelectionTests {
    private let context = ToolContext(workingDirectory: "/tmp")

    private func input(_ json: String) -> JSONObject { try! JSONObject(validating: Array(json.utf8)) }

    @Test func `the launch environment selects the shell`() async {
        let tool = BashTool(jobs: JobTable(environment: ["SHELL": "/bin/sh"]))
        let result = await tool.run(input(#"{"command":"printf '%s' \"$0\""}"#), in: context)
        #expect(result == ToolOutput("/bin/sh\n[exit 0]"))
    }

    @Test func `an explicit shell overrides the launch environment`() async {
        let tool = BashTool(jobs: JobTable(environment: ["SHELL": "/bin/sh"]))
        let result = await tool.run(input(#"{"command":"printf '%s' \"$0\"","shell":"/bin/bash"}"#), in: context)
        #expect(result == ToolOutput("/bin/bash\n[exit 0]"))
    }

    @Test func `an invalid environment shell falls back to bash`() async {
        let tool = BashTool(jobs: JobTable(environment: ["SHELL": "/nonexistent/shell"]))
        let result = await tool.run(input(#"{"command":"printf '%s' \"$0\""}"#), in: context)
        #expect(result == ToolOutput("/bin/bash\n[exit 0]"))
    }
}
