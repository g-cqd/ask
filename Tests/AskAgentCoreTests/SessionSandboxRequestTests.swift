import AskAI
import Synchronization
import Testing

@testable import AskAgentCore

/// The model narrows the whole session through a call's own `sandbox` (roadmap 0019, ADR-0162): every later call runs inside it,
/// a later narrowing of one dimension keeps the others, and asking for more, or resetting, needs the user.
@Suite("A call can keep its narrowing for the session; undoing it is the user's to allow")
struct SessionSandboxRequestTests {
    /// Records the policy each call ran under.
    private final class Spy: Tool {
        let definition = ToolDefinition(name: "spy", description: "Record.") { SandboxRequest.propertyWithSession }
        let seen = Mutex<[SandboxPolicy]>([])
        func run(_ input: JSONObject, in context: ToolContext) async -> ToolOutput {
            seen.withLock { $0.append(context.sandbox) }
            return ToolOutput("ran")
        }
    }

    private let workspace = "/opt/ask-narrow-test"
    private let spy = Spy()
    private let narrowing = SessionNarrowing()

    private func call(
        _ sandbox: String? = nil,
        run: SandboxPolicy = SandboxPolicy(),
        busy: Bool = false,
        approve: SandboxApprover? = nil
    ) async throws -> ToolOutput {
        let json = sandbox.map { #"{"sandbox":\#($0)}"# } ?? "{}"
        let registry = try ToolRegistry([spy], busy: { busy })
        return await registry.run(
            name: "spy",
            input: try JSONObject(validating: Array(json.utf8)),
            in: ToolContext(workingDirectory: workspace, sandbox: run, approve: approve, narrowing: narrowing)
        )
    }

    private var ran: [SandboxPolicy.Network] { spy.seen.withLock { $0.map(\.network) } }
    private var last: SandboxPolicy? { spy.seen.withLock { $0.last } }

    @Test func `a narrowing kept for the session applies to that call and to every later one`() async throws {
        let said = try await call(#"{"network":"none","session":"keep"}"#)
        #expect(said == ToolOutput("Narrowed for the rest of the session.\nran"))
        #expect(try await call() == ToolOutput("ran"), "a later call is told nothing of it")
        #expect(ran == [.none, .none])
    }

    @Test func `a narrowing that is not kept is that call's alone`() async throws {
        #expect(try await call(#"{"network":"none"}"#) == ToolOutput("ran"))
        _ = try await call()
        #expect(ran == [.none, .any] && narrowing.policy == nil)
    }

    @Test func `narrowing another dimension keeps what was narrowed before`() async throws {
        _ = try await call(#"{"network":"none","session":"keep"}"#)
        _ = try await call(#"{"write":["."],"session":"keep"}"#)
        _ = try await call()
        #expect(last?.network == SandboxPolicy.Network.none && last?.write == .roots([workspace]))
    }

    @Test func `asking the session for more is refused without the user, and allowed with them`() async throws {
        _ = try await call(#"{"network":"none","session":"keep"}"#)
        let refused = try await call(#"{"network":"any","session":"keep"}"#)
        #expect(refused == .error("Not permitted: that request is refused."))
        #expect(narrowing.policy?.network == SandboxPolicy.Network.none, "a refused request keeps nothing")
        let asked = Mutex<[SandboxApproval]>([])
        _ = try await call(#"{"network":"any","session":"keep"}"#) { approval in
            asked.withLock { $0.append(approval) }
            return true
        }
        _ = try await call()
        #expect(last?.network == .any)
        #expect(asked.withLock { $0.map(\.request) } == [SandboxRequest(network: .any)], "a grant remembers no session")
    }

    @Test func `reset is a widening: refused without the user, allowed with them`() async throws {
        _ = try await call(#"{"network":"none","session":"keep"}"#)
        let refused = try await call(#"{"session":"reset"}"#)
        #expect(refused == .error("Not permitted: that request is refused."))
        _ = try await call()
        #expect(ran == [.none, .none], "still narrowed, and the refused call did not run")
        let asked = Mutex<[SandboxApproval]>([])
        let reset = try await call(#"{"session":"reset"}"#) { approval in
            asked.withLock { $0.append(approval) }
            return true
        }
        #expect(reset == ToolOutput("The session's narrowing is undone.\nran"))
        let question = asked.withLock { $0.first }
        #expect(
            question?.asked == ["the run's own sandbox back, undoing the session's narrowing"]
                && question?.request == nil
        )
        _ = try await call()
        #expect(
            ran == [.none, .none, .any, .any],
            "the call that reset ran under the run's own sandbox, as later ones do"
        )
    }

    @Test func `a user who says no to a reset keeps the session narrowed`() async throws {
        _ = try await call(#"{"network":"none","session":"keep"}"#)
        let refused = try await call(#"{"session":"reset"}"#) { _ in false }
        #expect(refused.isError)
        _ = try await call()
        #expect(ran == [.none, .none])
    }

    @Test func `a reset may narrow its own call, and one with nothing to undo asks no one`() async throws {
        let nothing = try await call(#"{"session":"reset"}"#) { _ in
            Issue.record("nothing was narrowed, so nothing is asked")
            return false
        }
        #expect(nothing == ToolOutput("The session was not narrowed; nothing to reset.\nran"))
        _ = try await call(#"{"network":"none","session":"keep"}"#)
        _ = try await call(#"{"network":"localhost","session":"reset"}"#) { _ in true }
        _ = try await call()
        #expect(ran == [.any, .none, .localhost, .any])
    }

    @Test func `the session narrowing never reaches past the run`() async throws {
        narrowing.policy = SandboxPolicy(network: .any)
        _ = try await call(run: SandboxPolicy(network: .localhost))
        #expect(last?.network == .localhost)
    }

    @Test func `what the user grants one call is kept only up to the run's ceiling, which the model is not told`()
        async throws
    {
        let run = SandboxPolicy(network: .localhost)
        let output = try await call(#"{"network":"any","session":"keep"}"#, run: run) { _ in true }
        #expect(
            output == ToolOutput("Narrowed for the rest of the session.\nran"),
            "the ceiling is not told to the model"
        )
        #expect(narrowing.policy?.network == .localhost)
        _ = try await call(run: run)
        #expect(ran == [.any, .localhost], "the granted call ran with what was granted; the session keeps the ceiling")
    }

    @Test func `stop what runs before promising a session-wide narrowing`() async throws {
        let output = try await call(#"{"network":"none","session":"keep"}"#, busy: true)
        #expect(output.isError && output.content.contains("Stop running jobs first"))
        #expect(narrowing.policy == nil && ran.isEmpty, "nothing kept, and the call did not run")
        let alone = try await call(#"{"network":"none"}"#, busy: true)
        #expect(alone == ToolOutput("ran"), "one call's own narrowing starts a process of its own")
    }

    @Test(arguments: [
        (#"{"session":"keep"}"#, "needs a network, write or read to keep"),
        (#"{"network":"none","session":"always"}"#, #"session is keep or reset, not "always""#)
    ])
    func `a session request that says nothing to keep, or a word that is neither, is refused with why`(
        _ sandbox: String,
        _ why: String
    ) async throws {
        let output = try await call(sandbox)
        #expect(output.isError && output.content.contains(why), "\(output.content)")
        #expect(narrowing.policy == nil && ran.isEmpty)
    }

    @Test func `a run that keeps no session sandbox says so`() async throws {
        let input = try JSONObject(validating: Array(#"{"sandbox":{"network":"none","session":"keep"}}"#.utf8))
        let registry = try ToolRegistry([spy])
        let output = await registry.run(name: "spy", input: input, in: ToolContext(workingDirectory: workspace))
        #expect(output == .error("This run does not keep a session sandbox."))
    }
}
