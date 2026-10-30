import AskAI
import Testing

@testable import AskAgentCore

/// `--ask NAME` (roadmap 0154): the command line adds to `approvals.ask` for one run, which wins over what the file allows; `commands`
/// names every command.
@Suite("Asking about chosen tool calls for one run")
struct ApprovalAskWordsTests {
    private func input(_ json: String) -> JSONObject { try! JSONObject(validating: Array(json.utf8)) }

    private func asks(_ policy: ApprovalPolicy, _ tool: String, _ json: String = "{}") -> Bool {
        if case .ask = policy.decide(tool: tool, input: input(json), workingDirectory: "/p") { return true }
        return false
    }

    @Test func `a name asked about on the command line asks, even when the file allows it`() {
        let policy = ApprovalPolicy(section: ApprovalsSection(allow: ["write", "bash"]), asking: ["write"])
        #expect(asks(policy, "write", #"{"path":"a"}"#))
        #expect(!asks(policy, "bash", #"{"command":"ls"}"#), "only what was named")
    }

    @Test func `commands asks before every command, read-only tools stay quiet`() {
        let policy = ApprovalPolicy(section: ApprovalsSection(defaultMode: .allow), asking: ["commands"])
        #expect(asks(policy, "bash", #"{"command":"ls"}"#))
        #expect(!asks(policy, "write", #"{"path":"a"}"#), "the file's default still allows the rest")
        #expect(!asks(policy, "read", #"{"path":"a"}"#))
    }
}
