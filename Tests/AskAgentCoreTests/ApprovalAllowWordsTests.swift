import AskAI
import Testing

@testable import AskAgentCore

/// "Allow all tool calls" and "allow all commands" (roadmap 0156): the words `all` and `commands` in `approvals.allow`, and the same
/// list from the command line (`--allow`), added to the file's for one run.
@Suite("Allowing all tool calls, or all commands")
struct ApprovalAllowWordsTests {
    private func input(_ json: String) -> JSONObject { try! JSONObject(validating: Array(json.utf8)) }

    private func decide(_ policy: ApprovalPolicy, _ tool: String, _ json: String = "{}") -> ApprovalPolicy.Decision {
        policy.decide(tool: tool, input: input(json), workingDirectory: "/p")
    }

    private func asks(_ decision: ApprovalPolicy.Decision) -> Bool {
        if case .ask = decision { return true }
        return false
    }

    @Test func `commands allows every command, and nothing else`() {
        let policy = ApprovalPolicy(section: ApprovalsSection(allow: ["commands"]))
        #expect(decide(policy, "bash", #"{"command":"rm -rf build"}"#) == .run)
        #expect(asks(decide(policy, "write", #"{"path":"a"}"#)))
        #expect(asks(decide(policy, "job", #"{"action":"input"}"#)))
    }

    @Test func `all allows every tool call, MCP tools' own questions included`() {
        let policy = ApprovalPolicy(section: ApprovalsSection(allow: ["all"]))
        #expect(
            decide(policy, "bash", #"{"command":"rm x"}"#) == .run && decide(policy, "write", #"{"path":"a"}"#) == .run)
        #expect(decide(policy, "mcp__srv__boom") == .runWithoutServerQuestion)
    }

    @Test func `the command line adds to the file's list for the run`() {
        let policy = ApprovalPolicy(section: ApprovalsSection(allow: ["write"]), allowing: ["commands"])
        #expect(
            decide(policy, "bash", #"{"command":"ls"}"#) == .run && decide(policy, "write", #"{"path":"a"}"#) == .run)
        #expect(asks(decide(policy, "edit", #"{"path":"a"}"#)))
    }

    @Test func `the ask list still wins, and --ask-always ignores the allowing`() {
        #expect(
            asks(
                decide(
                    ApprovalPolicy(section: ApprovalsSection(allow: ["all"], ask: ["write"])), "write", #"{"path":"a"}"#
                )))
        #expect(asks(decide(ApprovalPolicy(flag: .askAlways, allowing: ["all"]), "bash", #"{"command":"ls"}"#)))
    }
}
