import AemiTesting
import AskAI
import AskAgentCore
import Foundation
import Testing

@testable import AskTools

@Suite("Shell readiness is bounded, cancellable and cannot observe protected paths", .timeLimit(.minutes(1)))
struct ShellReadinessTests {
    private let root = FileManager.default.temporaryDirectory.appending(path: "ask-ready-\(UUID().uuidString)")
    private let jobs = JobTable(environment: ["SHELL": "/bin/bash", "PATH": "/usr/bin:/bin"])

    private func context(_ policy: SandboxPolicy = .unrestricted) throws -> ToolContext {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return ToolContext(workingDirectory: root.path, sandbox: policy)
    }
    private func input(_ json: String) -> JSONObject { try! JSONObject(validating: Array(json.utf8)) }

    @Test func `file readiness returns an associated background job when a nested file appears`() async throws {
        let context = try context()
        let seen = Printed("ready")
        let tool = BashTool(jobs: jobs, clock: TestClock()) { if case .output(let bytes) = $0 { seen.received(bytes) } }
        let task = Task {
            await tool.run(
                input(#"{"command":"echo ready; read hold","wait_for_file":"out/flag","timeout_seconds":7}"#),
                in: context)
        }
        await seen.seen()
        try FileManager.default.createDirectory(at: root.appending(path: "out"), withIntermediateDirectories: true)
        try Data().write(to: root.appending(path: "out/flag"))
        let output = await task.value
        let running = jobs.running
        await jobs.stopAll()
        #expect(!output.isError && output.content.contains("out/flag") && output.content.contains("exists"))
        #expect(output.backgroundJob == "job-1" && running == ["job-1"])
    }

    @Test func `readiness timeout uses timeout_seconds instead of yield_seconds and stops the launch`() async throws {
        let context = try context()
        let clock = TestClock()
        let seen = Printed("ready")
        let tool = BashTool(jobs: jobs, clock: clock) { if case .output(let bytes) = $0 { seen.received(bytes) } }
        let task = Task {
            await tool.run(
                input(
                    #"{"command":"echo ready; read hold","wait_for_file":"missing","yield_seconds":1,"timeout_seconds":7}"#
                ), in: context)
        }
        await seen.seen()
        try await clock.waitForSleepers(count: 1)
        clock.advance(by: .seconds(7))
        let output = await task.value
        let running = jobs.running
        await jobs.stopAll()
        #expect(output.isError && output.content.contains("timed out after 7 s"))
        #expect(output.backgroundJob == nil && running.isEmpty)
    }

    @Test(arguments: ["file", "port"])
    func `cancelling readiness stops the launch and reports aborted not timed out`(_ kind: String) async throws {
        let context = try context()
        if kind == "port" { try #require(!PortWait.accepts(65_535)) }
        let seen = Printed("ready")
        let tool = BashTool(jobs: jobs, clock: TestClock()) { if case .output(let bytes) = $0 { seen.received(bytes) } }
        let condition = kind == "file" ? #""wait_for_file":"missing""# : #""wait_for_port":65535"#
        let task = Task { await tool.run(input(#"{"command":"echo ready; read hold",\#(condition)}"#), in: context) }
        await seen.seen()
        task.cancel()
        let output = await task.value
        let running = jobs.running
        await jobs.stopAll()
        #expect(output.isError && output.content.contains("aborted") && !output.content.contains("within"))
        #expect(running.isEmpty)
    }

    @Test(arguments: [
        #""wait_for_output":"x","wait_for_file":"flag""#,
        #""wait_for_port":0"#, #""wait_for_port":65536"#,
        #""wait_for_output":"""#, #""wait_for_file":"""#
    ])
    func `invalid or ambiguous readiness is rejected before launching`(_ fields: String) async throws {
        let output = await BashTool(jobs: jobs).run(input(#"{"command":"true",\#(fields)}"#), in: try context())
        #expect(output.isError)
        #expect(jobs.job("job-1") == nil)
    }

    @Test func `protected files and network-disabled ports are rejected before launching`() async throws {
        let context = try context(
            SandboxPolicy(
                network: .none,
                denyRead: [
                    SandboxRule(CanonicalPath.of(root.appending(path: "protected").path, relativeTo: "/")!, .subpath)
                ]))
        for fields in [#""wait_for_file":"protected/flag""#, #""wait_for_port":65535"#] {
            let output = await BashTool(jobs: jobs).run(input(#"{"command":"true",\#(fields)}"#), in: context)
            #expect(output.isError && output.content.lowercased().contains("not permitted"))
            #expect(jobs.job("job-1") == nil)
        }
    }

    @Test func `a directory swapped for a protected symlink cannot satisfy readiness`() async throws {
        let policy = SandboxPolicy(denyRead: [
            SandboxRule(CanonicalPath.of(root.appending(path: "protected").path, relativeTo: "/")!, .subpath)
        ])
        let context = try context(policy)
        for directory in ["out", "protected"] {
            try FileManager.default.createDirectory(
                at: root.appending(path: directory), withIntermediateDirectories: true)
        }
        try Data().write(to: root.appending(path: "protected/flag"))
        let seen = Printed("ready")
        let tool = BashTool(jobs: jobs, clock: TestClock()) { if case .output(let bytes) = $0 { seen.received(bytes) } }
        let task = Task {
            await tool.run(input(#"{"command":"echo ready; read hold","wait_for_file":"out/flag"}"#), in: context)
        }
        await seen.seen()
        try FileManager.default.moveItem(at: root.appending(path: "out"), to: root.appending(path: "old"))
        try FileManager.default.createSymbolicLink(
            atPath: root.appending(path: "out").path,
            withDestinationPath: root.appending(path: "protected").path)
        let output = await task.value
        let running = jobs.running
        await jobs.stopAll()
        #expect(output.isError && output.content.lowercased().contains("not permitted"))
        #expect(!output.content.contains(root.appending(path: "protected").path))
        #expect(running.isEmpty)
    }
}
