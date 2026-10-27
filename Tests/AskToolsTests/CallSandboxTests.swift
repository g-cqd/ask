import AemiTesting
import AskAI
import AskAgentCore
import Foundation
import Testing

@testable import AskTools

/// A call's own sandbox, under the real `sandbox-exec`: what the call narrowed holds even though the run allows more.
@Suite("A call's narrowed sandbox holds under the real sandbox-exec", .timeLimit(.minutes(2)))
final class CallSandboxTests {
    private let world: SandboxWorld

    // Not under the temporary directory, which every sandbox keeps writable and readable as scratch.
    init() throws { world = try SandboxWorld(outsideScratch: true) }

    deinit { try? FileManager.default.removeItem(atPath: world.home) }

    private func bash(_ command: String, sandbox: String) async throws -> ToolOutput {
        let registry = try ToolRegistry([BashTool(), WriteTool()])
        let quoted = command.replacingOccurrences(of: "\"", with: "\\\"")
        return await registry.run(
            name: "bash", input: world.input(#"{"command":"\#(quoted)","sandbox":\#(sandbox),"shell":"/bin/bash"}"#),
            in: world.context)
    }

    @Test func `a call narrowed to a subdirectory cannot write beside it, though the run could`() async throws {
        try FileManager.default.createDirectory(atPath: world.workspace + "/sub", withIntermediateDirectories: true)
        let inside = try await bash("echo in > sub/a.txt && cat sub/a.txt", sandbox: #"{"write":["sub"]}"#)
        #expect(inside == ToolOutput("in\n[exit 0]"))
        let beside = try await bash("echo out > b.txt", sandbox: #"{"write":["sub"]}"#)
        #expect(beside.isError && beside.content.contains("Operation not permitted"))
        #expect(!FileManager.default.fileExists(atPath: world.workspace + "/b.txt"))
        #expect(
            try await bash("echo out > b.txt && echo ok", sandbox: "{}") == ToolOutput("ok\n[exit 0]"),
            "the run itself may")
    }

    @Test func `a call narrowed to reading the workspace cannot read the rest of the home`() async throws {
        let output = try await bash("cat '\(world.home)/.ssh/config'", sandbox: #"{"read":["."]}"#)
        #expect(output.isError && !output.content.contains("Host *"))
    }

    @Test func `the write tool follows a call's narrowing too`() async throws {
        let registry = try ToolRegistry([WriteTool()])
        let output = await registry.run(
            name: "write", input: world.input(#"{"path":"c.txt","content":"x","sandbox":{"write":["sub"]}}"#),
            in: world.context)
        #expect(output == .error("Not permitted: c.txt."))
    }
}
