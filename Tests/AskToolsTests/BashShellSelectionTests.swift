import AskAI
import AskAgentCore
import Testing

@testable import AskTools

@Suite("Commands run in the configured shell, else bash, a POSIX shell or the login shell (roadmaps 0091 and 0188)")
struct BashShellSelectionTests {
    private let context = ToolContext(workingDirectory: "/tmp")

    private func input(_ json: String) -> JSONObject { try! JSONObject(validating: Array(json.utf8)) }

    private let printShell = #"{"command":"printf '%s' \"$0\""}"#

    private func shell(
        login: String? = "/bin/sh",
        configured: String? = nil,
        argument: String? = nil
    ) async -> ToolOutput {
        let tool = BashTool(jobs: JobTable(environment: login.map { ["SHELL": $0] } ?? [:]))
        let scoped = ToolContext(workingDirectory: "/tmp", commandEnvironment: CommandEnvironment(shell: configured))
        let json = argument.map { #"{"command":"printf '%s' \"$0\"","shell":"\#($0)"}"# } ?? printShell
        return await tool.run(input(json), in: scoped)
    }

    @Test func `nothing chosen, bash comes first even when the login shell is another`() async {
        #expect(await shell(login: "/bin/zsh") == ToolOutput("/bin/bash\n[exit 0]"))
    }

    /// The default for a machine with only the shells in `present`, the PATH `path`, and the login shell `login`.
    private func fallback(_ present: Set<String>, path: String = "/p1:/p2", login: String? = "/bin/zsh") -> String {
        JobTable.defaultShell(path: path, login: login) { present.contains($0) }
    }

    @Test func `the order is bash on the PATH, /bin/bash, then ksh, sh and dash, then the login shell`() {
        let all: Set = ["/p2/bash", "/bin/bash", "/p1/ksh", "/bin/ksh", "/p1/sh", "/bin/sh", "/bin/dash", "/bin/zsh"]
        #expect(fallback(all) == "/p2/bash")
        #expect(fallback(all.subtracting(["/p2/bash"])) == "/bin/bash")
        let noBash = all.subtracting(["/p2/bash", "/bin/bash"])
        #expect(fallback(noBash) == "/p1/ksh", "a POSIX shell on the PATH, the closest to bash first")
        #expect(fallback(noBash.subtracting(["/p1/ksh"])) == "/p1/sh", "the PATH before the system's folders")
        #expect(fallback(["/bin/ksh", "/bin/sh", "/bin/dash", "/bin/zsh"]) == "/bin/ksh")
        #expect(fallback(["/bin/sh", "/bin/dash", "/bin/zsh"]) == "/bin/sh")
        #expect(fallback(["/usr/bin/dash", "/bin/zsh"]) == "/usr/bin/dash")
        #expect(fallback(["/bin/zsh"]) == "/bin/zsh", "then the login shell; zsh is no longer a default of its own")
        #expect(fallback(["/bin/zsh", "/opt/x/fish"], login: "/opt/x/fish") == "/opt/x/fish")
        #expect(fallback([], login: nil) == "/bin/sh", "nothing found: the system's POSIX shell")
    }

    @Test func `on this machine, nothing chosen is bash`() {
        let chosen = JobTable(environment: ["SHELL": "/bin/sh"]).commandShell(nil, policy: .inherit)
        #expect(chosen.hasSuffix("/bash"))
    }

    @Test func `a configured shell name beats the default`() async {
        #expect(await shell(configured: "bash") == ToolOutput("/bin/bash\n[exit 0]"))
        #expect(await shell(configured: "sh") == ToolOutput("/bin/sh\n[exit 0]"))
    }

    @Test func `a configured absolute path that the system lists is used`() async {
        #expect(await shell(configured: "/bin/sh") == ToolOutput("/bin/sh\n[exit 0]"))
    }

    @Test func `a configured shell that is missing or not listed falls back to the default`() async {
        let expected = ToolOutput("/bin/bash\n[exit 0]")
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

    @Test func `macOS's own bash is named as 3.2 in the description, so the model writes for it`() {
        let tool = BashTool(jobs: JobTable(environment: ["PATH": "/bin"]))
        #expect(tool.definition.description.contains("/bin/bash") && tool.definition.description.contains("3.2"))
    }

    @Test func `the tool's description names the shell it will use`() {
        let tool = BashTool(jobs: JobTable(), commandEnvironment: CommandEnvironment(shell: "sh"))
        #expect(tool.definition.description.contains("/bin/sh"))
    }
}
