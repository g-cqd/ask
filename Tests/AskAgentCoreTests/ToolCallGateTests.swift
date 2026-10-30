internal import AskAI
internal import Synchronization
internal import Testing

@testable import AskAgentCore

/// The registry puts a call the policy says asks to the person before it runs (roadmap 0134); without a gate, as in `ask -p`, it runs.
@Suite("The tool registry asks before a call that changes things")
struct ToolCallGateTests {
    private final class Asked: Sendable {
        let calls = Mutex<[ToolCallApproval]>([])
        let answer: Bool
        init(_ answer: Bool) { self.answer = answer }
        func gate(_ policy: ApprovalPolicy = ApprovalPolicy()) -> ToolCallGate {
            ToolCallGate(policy: policy) { [self] approval in
                calls.withLock { $0.append(approval) }
                return answer
            }
        }
    }

    private func input(_ json: String) -> JSONObject { try! JSONObject(validating: Array(json.utf8)) }

    @Test func `a call that asks runs once allowed, and not when denied`() async throws {
        let tool = CountingTool("bash")
        let registry = try ToolRegistry([tool])
        let yes = Asked(true)
        let ran = await registry.run(
            name: "bash", input: input(#"{"command":"ls"}"#),
            in: ToolContext(workingDirectory: "/p", callGate: yes.gate()))
        #expect(ran == ToolOutput("ran") && tool.count == 1 && yes.calls.withLock { $0.count } == 1)
        let no = Asked(false)
        let refused = await registry.run(
            name: "bash", input: input(#"{"command":"ls"}"#),
            in: ToolContext(workingDirectory: "/p", callGate: no.gate()))
        #expect(refused.isError && refused.content.contains("did not allow") && tool.count == 1)
    }

    @Test func `without a gate, or for a read-only tool, nothing is asked`() async throws {
        let bash = CountingTool("bash")
        let read = CountingTool("read")
        let registry = try ToolRegistry([bash, read])
        _ = await registry.run(
            name: "bash", input: input(#"{"command":"ls"}"#), in: ToolContext(workingDirectory: "/p"))
        let asked = Asked(false)
        _ = await registry.run(
            name: "read", input: input(#"{"path":"a"}"#),
            in: ToolContext(workingDirectory: "/p", callGate: asked.gate()))
        #expect(bash.count == 1 && read.count == 1 && asked.calls.withLock { $0.isEmpty })
    }

    @Test func `mcp_call is judged under the name of the tool it calls`() {
        let policy = ApprovalPolicy(section: ApprovalsSection(ask: ["mcp__docs__read"]))
        let decision = policy.decide(
            tool: "mcp_call", input: input(#"{"server":"docs","tool":"read","arguments":{}}"#), workingDirectory: "/p")
        guard case .ask(let approval) = decision else { return #expect(Bool(false), "not asked") }
        #expect(approval.scope == .tool("mcp__docs__read"))
    }
}
