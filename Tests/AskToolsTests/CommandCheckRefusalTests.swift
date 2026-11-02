import AskAI
import AskAgentCore
import Foundation
import Testing

@testable import AskTools

/// shellcheck's findings stop a command before it runs, once (the owner's choice, 2026-11-02): the model reads them at once instead of
/// waiting on a flawed command, and sending the same command again runs it as written. A check that ran past its deadline lets the
/// command run, and the result says it was not checked.
@Suite("A command shellcheck finds fault with is refused once, and an unchecked one says so")
struct CommandCheckRefusalTests {
    private static let shellcheck = ["/opt/homebrew/bin/shellcheck", "/usr/local/bin/shellcheck"]
        .first {
            FileManager.default.isExecutableFile(atPath: $0)
        }

    private func input(_ command: String) throws -> JSONObject {
        let quoted = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return try JSONObject(validating: Array(#"{"command":"\#(quoted)"}"#.utf8))
    }

    private func tool() -> BashTool {
        let path = (Self.shellcheck! as NSString).deletingLastPathComponent + ":/usr/bin:/bin"
        return BashTool(jobs: JobTable(environment: ["PATH": path]))
    }

    @Test(.enabled(if: shellcheck != nil))
    func `a command with findings is refused with them, runs when sent again, and is refused again after`() async throws
    {
        let marker = NSTemporaryDirectory() + "ask-refused-\(UUID().uuidString)"
        let tool = tool()
        let context = ToolContext(workingDirectory: "/tmp")
        let command = "cd /nonexistent-ask-dir; touch \(marker)"
        let first = await tool.run(try input(command), in: context)
        #expect(
            first.isError && first.content.contains("SC2164") && first.content.contains("send the same command again")
        )
        #expect(!FileManager.default.fileExists(atPath: marker), "nothing ran")
        let second = await tool.run(try input(command), in: context)
        #expect(FileManager.default.fileExists(atPath: marker), "sent again, it ran as written")
        #expect(!second.content.contains("send the same command again"))
        try? FileManager.default.removeItem(atPath: marker)
        let third = await tool.run(try input(command), in: context)
        #expect(third.content.contains("send the same command again"), "the second run used the permission up")
        #expect(!FileManager.default.fileExists(atPath: marker))
    }

    @Test(.enabled(if: shellcheck != nil))
    func `a command without findings runs at once, and another command's refusal does not let it through`() async throws
    {
        let tool = tool()
        let context = ToolContext(workingDirectory: "/tmp")
        #expect(await tool.run(try input("true"), in: context).content.hasSuffix("[exit 0]"))
        _ = await tool.run(try input("cd /nonexistent-a; true"), in: context)
        let other = await tool.run(try input("cd /nonexistent-b; true"), in: context)
        #expect(other.content.contains("send the same command again"))
    }

    @Test(
        .enabled(if: shellcheck != nil),
        arguments: ["echo $https_proxy", "echo ready; read -r hold", "echo x && echo done"]
    )
    func `a finding a single command cannot judge does not refuse it`(command: String) async throws {
        let output = await tool().run(try input(command), in: ToolContext(workingDirectory: "/tmp"))
        #expect(!output.content.contains("so it was not run"), "SC2154, SC2034 and SC1010 run at once")
    }

    @Test func `only findings a single command can judge refuse, and the others are still told on a failure`() {
        #expect(CommandCheck.refuses("1:1: warning: x is referenced but not assigned. [SC2154]") == false)
        #expect(CommandCheck.refuses("1:1: warning: hold appears unused. [SC2034]") == false)
        #expect(CommandCheck.refuses("1:9: warning: Use semicolon or linefeed before 'done'. [SC1010]") == false)
        #expect(CommandCheck.refuses("1:1: warning: Use 'cd ... || exit'. [SC2164]"))
        var failed = ToolOutput.error("[exit 1]")
        BashTool.annotate(
            &failed,
            CommandCheck.Result(findings: ["1:1: warning: x is referenced but not assigned. [SC2154]"])
        )
        #expect(failed.content.contains("[shellcheck]") && failed.content.contains("SC2154"))
    }

    /// A shell that takes a second to parse anything, standing in for a machine under heavy load.
    private func slowShell() throws -> String {
        let path = NSTemporaryDirectory() + "ask-slow-shell-\(UUID().uuidString)"
        try "#!/bin/sh\nsleep 1\nexit 0\n".write(toFile: path, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
        return path
    }

    @Test func `a check past its deadline is reported as unchecked, and a quick one is not`() async throws {
        let slow = try slowShell()
        defer { try? FileManager.default.removeItem(atPath: slow) }
        let checked = await CommandCheck.check(
            "echo hi",
            shell: slow,
            path: "/usr/bin:/bin",
            deadline: .milliseconds(100)
        )
        #expect(checked.unchecked && checked.syntaxError == nil)
        let quick = await CommandCheck.check("echo hi", shell: "/bin/bash", path: "/usr/bin:/bin")
        #expect(!quick.unchecked)
    }

    @Test func `an unchecked command's result says so, and a checked one's does not`() {
        var unchecked = ToolOutput("hi\n[exit 0]")
        BashTool.annotate(&unchecked, CommandCheck.Result(unchecked: true))
        #expect(
            unchecked.content
                == "hi\n[exit 0]\n[not checked: the shell's parse or shellcheck took more than its deadline]"
        )
        var checked = ToolOutput("hi\n[exit 0]")
        BashTool.annotate(&checked, CommandCheck.Result(findings: ["1:1: warning: x"]))
        #expect(checked.content == "hi\n[exit 0]", "findings go only with a failure")
    }

    @Test func `an unchecked command is not refused for that`() throws {
        try BashTool().refuse("echo hi", shell: "/bin/bash", CommandCheck.Result(unchecked: true))
    }
}
