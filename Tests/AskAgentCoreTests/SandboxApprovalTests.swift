import AskAI
import Foundation
import Synchronization
import Testing

@testable import AskAgentCore

/// A widening request may be put to the user (roadmap 0019): granted once it runs under what it asked for, with the
/// protections kept; a grant for the session covers later requests it contains; without an approver it is refused.
@Suite("A widening request is put to the user, and only the user grants it")
struct SandboxApprovalTests {
    private let workspace = "/opt/ask-approval-test"
    private func request(_ json: String) throws -> SandboxRequest {
        try #require(try SandboxRequest.in(JSONObject(validating: Array(json.utf8))))
    }

    @Test func `a granted request runs under what it asked for, protections kept`() throws {
        let policy = SandboxPolicy(
            network: .localhost, write: .roots([workspace]), denyRead: [SandboxRule(workspace + "/secret", .subpath)])
        let granted = try request(#"{"sandbox":{"network":"any","write":["/opt/other"]}}"#)
            .granted(over: policy, workingDirectory: workspace)
        #expect(granted.network == .any && granted.write == .roots(["/opt/other"]))
        #expect(granted.denyRead == policy.denyRead && granted.denyWrite == policy.denyWrite)
    }

    @Test func `a session grant covers requests it contains, and nothing beyond`() throws {
        let grants = [try request(#"{"sandbox":{"network":"localhost","write":["/opt/other"]}}"#)]
        #expect(try request(#"{"sandbox":{"network":"none"}}"#).isCovered(by: grants, workingDirectory: workspace))
        #expect(
            try request(#"{"sandbox":{"write":["/opt/other/deeper"]}}"#)
                .isCovered(by: grants, workingDirectory: workspace))
        #expect(!(try request(#"{"sandbox":{"network":"any"}}"#).isCovered(by: grants, workingDirectory: workspace)))
        #expect(
            !(try request(#"{"sandbox":{"write":["/opt/elsewhere"]}}"#)
                .isCovered(by: grants, workingDirectory: workspace)))
        #expect(
            !(try request(#"{"sandbox":{"read":["/opt/other"]}}"#).isCovered(by: grants, workingDirectory: workspace)),
            "a write grant is not a read grant")
        #expect(!(try request(#"{"sandbox":{"network":"none"}}"#).isCovered(by: [], workingDirectory: workspace)))
    }

    /// Records the policy each call ran under.
    private final class Spy: Tool {
        let definition = ToolDefinition(name: "spy", description: "Record.") { ToolProperty.string("x").optional }
        let seen = Mutex<[SandboxPolicy]>([])
        func run(_ input: JSONObject, in context: ToolContext) async -> ToolOutput {
            seen.withLock { $0.append(context.sandbox) }
            return ToolOutput("ran")
        }
    }

    private func run(_ json: String, approve: SandboxApprover?) async throws -> (ToolOutput, [SandboxPolicy]) {
        let spy = Spy()
        let output = try await ToolRegistry([spy])
            .run(
                name: "spy", input: try JSONObject(validating: Array(json.utf8)),
                in: ToolContext(
                    workingDirectory: workspace, sandbox: SandboxPolicy(network: .localhost), approve: approve))
        return (output, spy.seen.withLock { $0 })
    }

    @Test func `an approved widening runs, under the widened policy, and the user was asked what it wants`()
        async throws
    {
        let asked = Mutex<[SandboxApproval]>([])
        let (output, seen) = try await run(#"{"x":"a","sandbox":{"network":"any"}}"#) { approval in
            asked.withLock { $0.append(approval) }
            return true
        }
        #expect(output == ToolOutput("ran") && seen == [SandboxPolicy(network: .any)])
        let question = try #require(asked.withLock { $0.first })
        #expect(question.tool == "spy" && question.asked == ["network any (this run allows localhost)"])
        #expect(String(decoding: question.input.bytes, as: UTF8.self).contains(#""x":"a""#))
    }

    @Test func `a refused widening does not run`() async throws {
        let (output, seen) = try await run(#"{"sandbox":{"network":"any"}}"#) { _ in false }
        #expect(output.isError && output.content == "Not permitted: that request is refused." && seen.isEmpty)
    }

    @Test func `narrowing never asks`() async throws {
        let asked = Mutex(0)
        let (output, _) = try await run(#"{"sandbox":{"network":"none"}}"#) { _ in
            asked.withLock { $0 += 1 }
            return true
        }
        #expect(output == ToolOutput("ran") && asked.withLock { $0 } == 0)
    }
}
