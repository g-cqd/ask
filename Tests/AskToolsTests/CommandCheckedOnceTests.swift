import AskAI
import AskAgentCore
import Foundation
import Testing

@testable import AskTools

/// A command the check had nothing to say about is not checked again by the same tool (the owner, 2026-11-14): an agent repeats its
/// build and test commands, and the check is 30 ms each time. Anything the check did say is read again every time.
@Suite("A command found clean is checked once", .timeLimit(.minutes(1)))
struct CommandCheckedOnceTests {
    private func input(_ command: String, shell: String) throws -> JSONObject {
        try JSONObject(validating: Array(#"{"command":"\#(command)","shell":"\#(shell)"}"#.utf8))
    }

    @Test func `a clean command is checked once, then only run`() async throws {
        let fixture = try CheckFixture(shellcheck: "exit 0")
        defer { fixture.remove() }
        let tool = BashTool(jobs: JobTable(environment: ["PATH": fixture.path]))
        let context = ToolContext(workingDirectory: "/tmp")
        for _ in 1 ... 3 {
            let output = await tool.run(try input("echo ok", shell: fixture.shell), in: context)
            #expect(!output.isError && output.content.contains("ok"))
        }
        #expect(fixture.log.filter { $0 == "-n" }.count == 1, "one parse")
        #expect(fixture.log.filter { $0 == "lint" }.count == 1, "one shellcheck")
        #expect(fixture.log.filter { $0 == "-c" }.count == 3, "three runs")
        _ = await tool.run(try input("echo other", shell: fixture.shell), in: context)
        #expect(fixture.log.filter { $0 == "-n" }.count == 2, "another command is checked")
    }

    @Test func `a command with something to say is checked every time`() async throws {
        // A finding that does not refuse (SC2034) is told again with each failure, so it is read again each time.
        let fixture = try CheckFixture(shellcheck: "echo '-:1:1: warning: x appears unused. [SC2034]'")
        defer { fixture.remove() }
        let tool = BashTool(jobs: JobTable(environment: ["PATH": fixture.path]))
        let context = ToolContext(workingDirectory: "/tmp")
        for _ in 1 ... 2 {
            let output = await tool.run(try input("x=1; exit 3", shell: fixture.shell), in: context)
            #expect(output.isError && output.content.contains("[shellcheck] 1:1: warning: x appears unused. [SC2034]"))
        }
        #expect(fixture.log.filter { $0 == "lint" }.count == 2)
        for _ in 1 ... 2 {
            let broken = await tool.run(try input("echo 'open", shell: fixture.shell), in: context)
            #expect(broken.isError && broken.content.contains("does not parse"))
        }
        #expect(fixture.log.filter { $0 == "-n" }.count == 4, "a command that does not parse is parsed each time")
    }
}
