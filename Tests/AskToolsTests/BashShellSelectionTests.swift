import AskAI
import AskAgentCore
import Testing

@testable import AskTools

@Suite("Commands run in the configured shell, else zsh, bash or the login shell (roadmap 0091)")
struct BashShellSelectionTests {
    private let context = ToolContext(workingDirectory: "/tmp")

    private func input(_ json: String) -> JSONObject { try! JSONObject(validating: Array(json.utf8)) }

    private let printShell = #"{"command":"printf '%s' \"$0\""}"#

    private func shell(
        login: String? = "/bin/sh", configured: String? = nil, argument: String? = nil
    ) async -> ToolOutput {
        let tool = BashTool(jobs: JobTable(environment: login.map { ["SHELL": $0] } ?? [:]))
        let scoped = ToolContext(workingDirectory: "/tmp", commandEnvironment: CommandEnvironment(shell: configured))
        let json = argument.map { #"{"command":"printf '%s' \"$0\"","shell":"\#($0)"}"# } ?? printShell
        return await tool.run(input(json), in: scoped)
    }

    @Test func `nothing chosen, zsh comes first even when the login shell is another`() async {
        #expect(await shell(login: "/bin/sh") == ToolOutput("/bin/zsh\n[exit 0]"))
    }

    @Test func `the order is zsh, then bash, then the login shell`() {
        let table = JobTable(environment: ["SHELL": "/bin/sh"])
        let chosen = table.commandShell(nil, policy: .inherit)
        #expect(chosen == (JobTable.isShell("/bin/zsh") ? "/bin/zsh" : "/bin/bash"))
        #expect(JobTable(environment: [:]).commandShell(nil, policy: .inherit) == chosen)
    }

    @Test func `a configured shell name beats the default`() async {
        #expect(await shell(configured: "bash") == ToolOutput("/bin/bash\n[exit 0]"))
        #expect(await shell(configured: "sh") == ToolOutput("/bin/sh\n[exit 0]"))
    }

    @Test func `a configured absolute path that the system lists is used`() async {
        #expect(await shell(configured: "/bin/sh") == ToolOutput("/bin/sh\n[exit 0]"))
    }

    @Test func `a configured shell that is missing or not listed falls back to the default`() async {
        let expected = ToolOutput("/bin/zsh\n[exit 0]")
        #expect(await shell(configured: "nonexistentshell") == expected)
        #expect(await shell(configured: "/usr/bin/python3") == expected)
        #expect(await shell(configured: "/nonexistent/shell") == expected)
    }

    @Test func `the model's own shell argument beats the configuration`() async {
        #expect(await shell(configured: "bash", argument: "/bin/sh") == ToolOutput("/bin/sh\n[exit 0]"))
    }

    @Test func `an executable that is not a shell cannot be named by the model`() async {
        #expect(await shell(configured: "sh", argument: "/usr/bin/python3") == ToolOutput("/bin/sh\n[exit 0]"))
    }

    @Test func `the tool's description names the shell it will use`() {
        let tool = BashTool(jobs: JobTable(), commandEnvironment: CommandEnvironment(shell: "sh"))
        #expect(tool.definition.description.contains("/bin/sh"))
    }
}
