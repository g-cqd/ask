import AemiTesting
import AskAI
import AskAgentCore
import Foundation
import Testing

@testable import AskTools

/// The read allow-list under the real `sandbox-exec`, and in the file tools: the workspace and the system are readable,
/// the rest of the home directory is not, and ordinary work still runs.
@Suite("Restricted reads hold under the real sandbox, and ordinary work still runs", .timeLimit(.minutes(2)))
final class ReadSandboxTests {
    private let world: SandboxWorld
    private let policy: SandboxPolicy

    deinit { try? FileManager.default.removeItem(atPath: world.home) }

    init() throws {
        // Not under the temporary directory: that is scratch space a restricted-read policy keeps readable.
        world = try SandboxWorld(outsideScratch: true)
        var restricted = world.policy
        restricted.read = .roots([world.workspace])
        policy = restricted
    }

    private func run(_ command: String) async -> ToolOutput {
        let quoted = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let context = ToolContext(workingDirectory: world.workspace, sandbox: policy)
        return await BashTool().run(world.input(#"{"command":"\#(quoted)","shell":"/bin/bash"}"#), in: context)
    }

    @Test func `the workspace and the system are readable, and programs run`() async {
        // Git's global config is a home file the executable adds to the roots; this policy has only the workspace.
        let output = await run(
            "cat file.txt; echo; /usr/bin/true && ls /usr/bin >/dev/null && GIT_CONFIG_GLOBAL=/dev/null git init -q . && echo ok"
        )
        #expect(output == ToolOutput("workspace file\nok\n[exit 0]"))
    }

    @Test func `the rest of the home directory cannot be read or listed`() async {
        #expect((await run("cat '\(world.home)/.ssh/config'")).isError, "readable by default, not in a read allow-list")
        #expect((await run("ls '\(world.home)'")).isError)
    }

    @Test func `the read tool follows the same allow-list`() async {
        let context = ToolContext(workingDirectory: world.workspace, sandbox: policy)
        let inside = await ReadTool().run(world.input(#"{"path":"file.txt"}"#), in: context)
        #expect(!inside.isError && inside.content.contains("workspace file"))
        let outside = await ReadTool().run(world.input(#"{"path":"\#(world.home)/.ssh/config"}"#), in: context)
        #expect(outside == .error("Not permitted: \(world.home)/.ssh/config."))
    }
}
