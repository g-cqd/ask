import AskAI
import AskAgentCore
import Foundation
import Testing

@testable import AskTools

@Suite("The default shell is the first zsh on the PATH, then the first bash, then SHELL (roadmap 0091)")
struct ShellPathOrderTests {
    /// A directory holding links called `names`, each to a real shell, placed on a test PATH.
    private func directory(_ names: [String: String]) throws -> String {
        let path = NSTemporaryDirectory() + "shells-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        for (name, target) in names {
            try FileManager.default.createSymbolicLink(atPath: path + "/" + name, withDestinationPath: target)
        }
        return path
    }

    private func chosen(_ environment: [String: String], shell: String? = nil) -> String {
        JobTable(environment: environment).commandShell(nil, policy: CommandEnvironment(shell: shell))
    }

    @Test func `the first zsh on the PATH wins over a later one and over bash`() throws {
        let first = try directory(["zsh": "/bin/zsh"])
        let second = try directory(["zsh": "/bin/zsh", "bash": "/bin/bash"])
        defer { for dir in [first, second] { try? FileManager.default.removeItem(atPath: dir) } }
        #expect(chosen(["PATH": "\(first):\(second)"]) == first + "/zsh")
        #expect(chosen(["PATH": "\(second):\(first)"]) == second + "/zsh")
    }

    @Test func `without zsh on the PATH, the first bash`() throws {
        let only = try directory(["bash": "/bin/bash"])
        defer { try? FileManager.default.removeItem(atPath: only) }
        #expect(chosen(["PATH": only, "SHELL": "/bin/sh"]) == only + "/bash")
    }

    @Test func `with neither on the PATH, the login shell`() throws {
        let empty = try directory([:])
        defer { try? FileManager.default.removeItem(atPath: empty) }
        #expect(chosen(["PATH": empty, "SHELL": "/bin/sh"]) == "/bin/sh")
        #expect(chosen(["PATH": empty]) == "/bin/bash", "nothing at all: bash, as before")
    }

    @Test func `a configured name is looked for on the PATH first`() throws {
        let dir = try directory(["sh": "/bin/sh"])
        defer { try? FileManager.default.removeItem(atPath: dir) }
        #expect(chosen(["PATH": dir], shell: "sh") == dir + "/sh")
    }

    @Test func `an unusable configured shell is named in a notice with the shell used instead`() throws {
        let dir = try directory(["zsh": "/bin/zsh"])
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let environment = ["PATH": dir]
        let missing = JobTable.unusableShellNotice(CommandEnvironment(shell: "nosuchshell"), environment: environment)
        #expect(
            missing
                == "environment.shell \"nosuchshell\" is not used: it is not on the PATH. Commands run in \(dir)/zsh.")
        let unlisted = JobTable.unusableShellNotice(
            CommandEnvironment(shell: "/usr/bin/python3"), environment: environment)
        #expect(unlisted?.contains("not an executable shell listed in /etc/shells") == true)
        #expect(JobTable.unusableShellNotice(CommandEnvironment(shell: "zsh"), environment: environment) == nil)
        #expect(JobTable.unusableShellNotice(CommandEnvironment(), environment: environment) == nil)
    }

    @Test func `zsh's description warns that an unmatched glob aborts the command, other shells' do not`() {
        let zsh = BashTool.makeDefinition(shell: "/bin/zsh").description
        let bash = BashTool.makeDefinition(shell: "/bin/bash").description
        #expect(zsh.contains("a glob that matches nothing aborts the command"))
        #expect(!bash.contains("glob"))
    }
}
