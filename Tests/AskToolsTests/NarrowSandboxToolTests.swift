import AskAI
import AskAgentCore
import Foundation
import Synchronization
import Testing

@testable import AskTools

/// The model narrows the whole session (roadmap 0019): every later call runs inside it, a later narrowing of one
/// dimension keeps the others, and asking for more, or resetting, needs the user.
@Suite("The model can narrow the whole session; undoing it is the user's to allow")
struct NarrowSandboxToolTests {
    /// Records the policy each call ran under.
    private final class Spy: Tool {
        let definition = ToolDefinition(name: "spy", description: "Record.") { ToolProperty.string("x").optional }
        let seen = Mutex<[SandboxPolicy]>([])
        func run(_ input: JSONObject, in context: ToolContext) async -> ToolOutput {
            seen.withLock { $0.append(context.sandbox) }
            return ToolOutput("ran")
        }
    }

    private let workspace = "/opt/ask-narrow-test"
    private let spy = Spy()

    private func call(
        _ name: String, _ json: String, narrowing: SessionNarrowing, sandbox: SandboxPolicy = SandboxPolicy(),
        approve: SandboxApprover? = nil
    ) async throws -> ToolOutput {
        let registry = try ToolRegistry([spy, NarrowSandboxTool()])
        return await registry.run(
            name: name, input: try JSONObject(validating: Array(json.utf8)),
            in: ToolContext(
                workingDirectory: workspace, sandbox: sandbox, approve: approve, narrowing: narrowing))
    }

    private var last: SandboxPolicy? { spy.seen.withLock { $0.last } }

    @Test func `a session narrowing applies to every later call`() async throws {
        let narrowing = SessionNarrowing()
        let said = try await call("narrow_sandbox", #"{"sandbox":{"network":"none"}}"#, narrowing: narrowing)
        #expect(!said.isError && said.content == "Narrowed for the rest of the session.")
        _ = try await call("spy", #"{}"#, narrowing: narrowing)
        #expect(last?.network == SandboxPolicy.Network.none)
    }

    @Test func `narrowing another dimension keeps what was narrowed before`() async throws {
        let narrowing = SessionNarrowing()
        _ = try await call("narrow_sandbox", #"{"sandbox":{"network":"none"}}"#, narrowing: narrowing)
        _ = try await call("narrow_sandbox", #"{"sandbox":{"write":["."]}}"#, narrowing: narrowing)
        _ = try await call("spy", #"{}"#, narrowing: narrowing)
        #expect(last?.network == SandboxPolicy.Network.none && last?.write == .roots([workspace]))
    }

    @Test func `asking the session for more is refused without the user, and allowed with them`() async throws {
        let narrowing = SessionNarrowing()
        _ = try await call("narrow_sandbox", #"{"sandbox":{"network":"none"}}"#, narrowing: narrowing)
        let refused = try await call("narrow_sandbox", #"{"sandbox":{"network":"any"}}"#, narrowing: narrowing)
        #expect(refused.isError && refused.content == "Not permitted: that request is refused.")
        _ = try await call("narrow_sandbox", #"{"sandbox":{"network":"any"}}"#, narrowing: narrowing) { _ in true }
        _ = try await call("spy", #"{}"#, narrowing: narrowing)
        #expect(last?.network == .any)
    }

    @Test func `reset is a widening: refused without the user, allowed with them`() async throws {
        let narrowing = SessionNarrowing()
        _ = try await call("narrow_sandbox", #"{"sandbox":{"network":"none"}}"#, narrowing: narrowing)
        let refused = try await call("narrow_sandbox", #"{"reset":true}"#, narrowing: narrowing)
        #expect(refused.isError && refused.content == "Not permitted: that request is refused.")
        _ = try await call("spy", #"{}"#, narrowing: narrowing)
        #expect(last?.network == SandboxPolicy.Network.none, "still narrowed")
        let asked = Mutex<[SandboxApproval]>([])
        let reset = try await call("narrow_sandbox", #"{"reset":true}"#, narrowing: narrowing) { approval in
            asked.withLock { $0.append(approval) }
            return true
        }
        #expect(
            !reset.isError
                && asked.withLock { $0.first?.asked } == ["the run's own sandbox back, undoing the session's narrowing"]
        )
        _ = try await call("spy", #"{}"#, narrowing: narrowing)
        #expect(last?.network == .any)
    }

    @Test func `a user who says no to a reset keeps the session narrowed`() async throws {
        let narrowing = SessionNarrowing()
        _ = try await call("narrow_sandbox", #"{"sandbox":{"network":"none"}}"#, narrowing: narrowing)
        let refused = try await call("narrow_sandbox", #"{"reset":true}"#, narrowing: narrowing) { _ in false }
        #expect(refused.isError)
        _ = try await call("spy", #"{}"#, narrowing: narrowing)
        #expect(last?.network == SandboxPolicy.Network.none)
    }

    @Test func `the session narrowing never reaches past the run`() async throws {
        let narrowing = SessionNarrowing()
        narrowing.policy = SandboxPolicy(network: .any)
        let registry = try ToolRegistry([spy])
        _ = await registry.run(
            name: "spy", input: try JSONObject(validating: Array("{}".utf8)),
            in: ToolContext(
                workingDirectory: workspace, sandbox: SandboxPolicy(network: .localhost), narrowing: narrowing))
        #expect(last?.network == .localhost)
    }

    @Test func `a session change keeps the run ceiling for later calls, without telling the model what it is`()
        async throws
    {
        let narrowing = SessionNarrowing()
        let policy = SandboxPolicy(network: .localhost)
        let output = try await call(
            "narrow_sandbox", #"{"sandbox":{"network":"any"}}"#, narrowing: narrowing, sandbox: policy
        ) { _ in true }
        #expect(output.content == "Narrowed for the rest of the session.", "the ceiling is not told to the model")
        #expect(narrowing.policy?.network == .localhost)
        _ = try await call("spy", #"{}"#, narrowing: narrowing, sandbox: policy)
        #expect(last?.network == .localhost)
    }

    @Test func `stop existing jobs before promising a session-wide narrowing`() async throws {
        let jobs = JobTable()
        let context = ToolContext(workingDirectory: "/tmp", narrowing: SessionNarrowing())
        let job = jobs.start("read -r line", in: context, keepsInputOpen: true, keeping: 128) { _ in }
        defer { job.stop() }
        let output = try await ToolRegistry([NarrowSandboxTool(jobs: jobs)])
            .run(
                name: "narrow_sandbox", input: JSONObject(validating: Array(#"{"sandbox":{"network":"none"}}"#.utf8)),
                in: context)
        job.stop()
        await job.ended()
        #expect(output.isError && output.content.contains("Stop running jobs first"))
        #expect(context.narrowing?.policy == nil)
    }

    @Test func `a call with neither sandbox nor reset says what it needs`() async throws {
        let output = try await call("narrow_sandbox", #"{}"#, narrowing: SessionNarrowing())
        #expect(output.isError && output.content.contains("sandbox") && output.content.contains("reset"))
    }
}
