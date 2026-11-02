import AskAI
import AskAgentCore
import Foundation
import Testing

@testable import AskTools

/// A command is checked by the shell that will run it before it runs (roadmap 0188): one that does not parse is not run, and the model
/// is told why; shellcheck's findings, where it is installed and the shell is bash or sh, come back with the result.
@Suite
struct CommandCheckTests {
    private static let shellcheck = ["/opt/homebrew/bin/shellcheck", "/usr/local/bin/shellcheck"]
        .first {
            FileManager.default.isExecutableFile(atPath: $0)
        }

    @Test(arguments: ["/bin/bash", "/bin/zsh", "/bin/sh"])
    func `a command that does not parse is caught by its own shell, and one that does passes`(shell: String) async {
        let broken = await CommandCheck.check(#"echo "unterminated"#, shell: shell, path: "/usr/bin:/bin")
        #expect(broken.syntaxError?.isEmpty == false)
        let fine = await CommandCheck.check("for f in *; do echo \"$f\"; done", shell: shell, path: "/usr/bin:/bin")
        #expect(fine.syntaxError == nil)
    }

    @Test
    func `parsing runs nothing: not the command, and in an environment of the PATH alone`() async throws {
        let marker = NSTemporaryDirectory() + "ask-check-\(UUID().uuidString)"
        _ = await CommandCheck.check("touch \(marker)", shell: "/bin/bash", path: "/usr/bin:/bin")
        #expect(!FileManager.default.fileExists(atPath: marker))
        #expect(
            CommandCheck.environment(path: "/usr/bin:/bin") == ["PATH": "/usr/bin:/bin"],
            "no BASH_ENV, ENV or ZDOTDIR to source"
        )
    }

    @Test
    func `no startup file or rc file takes part in a check`() {
        #expect(CommandCheck.parsing("x", with: "zsh").starts(with: ["-f", "-n"]))
        #expect(CommandCheck.parsing("x", with: "fish").starts(with: ["--no-config", "--no-execute"]))
        #expect(CommandCheck.parsing("x", with: "bash") == ["-n", "-c", "x"])
        #expect(CommandCheck.linting("bash").first == "--norc")
    }

    @Test
    func `the bash tool refuses a command that does not parse, and runs nothing`() async throws {
        let marker = NSTemporaryDirectory() + "ask-tool-check-\(UUID().uuidString)"
        let tool = BashTool(jobs: JobTable(environment: ["PATH": "/usr/bin:/bin"]))
        let input = try JSONObject(validating: Array(#"{"command":"touch \#(marker); echo \"oops"}"#.utf8))
        let output = await tool.run(input, in: ToolContext(workingDirectory: "/tmp"))
        #expect(output.isError && output.content.contains("does not parse"))
        #expect(!FileManager.default.fileExists(atPath: marker))
    }

    @Test(.enabled(if: shellcheck != nil))
    func `shellcheck reads a bash command, not a zsh one`() async throws {
        let path = (Self.shellcheck! as NSString).deletingLastPathComponent + ":/usr/bin:/bin"
        let checked = await CommandCheck.check("cd /nonexistent-dir; ls", shell: "/bin/bash", path: path)
        #expect(checked.findings.contains { $0.contains("SC2164") })
        let zsh = await CommandCheck.check("cd /nonexistent-dir; ls", shell: "/bin/zsh", path: path)
        #expect(zsh.findings.isEmpty, "shellcheck does not know zsh")
    }

    @Test(.enabled(if: shellcheck != nil))
    func `the findings come back with a failed command's result, sent again, and not with a successful one's`()
        async throws
    {
        let path = (Self.shellcheck! as NSString).deletingLastPathComponent + ":/usr/bin:/bin"
        let tool = BashTool(jobs: JobTable(environment: ["PATH": path]))
        let context = ToolContext(workingDirectory: "/tmp")
        let command = try JSONObject(validating: Array(#"{"command":"cd /nonexistent-ask-dir; false"}"#.utf8))
        _ = await tool.run(command, in: context)
        let failed = await tool.run(command, in: context)
        #expect(failed.isError && failed.content.contains("[shellcheck]") && failed.content.contains("SC2164"))
        #expect(failed.content.contains("[exit 1]"), "sent again, it ran")
        let fine = await tool.run(try JSONObject(validating: Array(#"{"command":"true"}"#.utf8)), in: context)
        #expect(!fine.isError && !fine.content.contains("[shellcheck]"))
    }
}
