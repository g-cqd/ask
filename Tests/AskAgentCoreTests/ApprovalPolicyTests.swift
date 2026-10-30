import AskAI
import Testing

@testable import AskAgentCore

/// Which calls ask the person (roadmap 0134): on by default, read-only tools exempt, the person's lists and the flags over that.
@Suite("Which tool calls are asked about")
struct ApprovalPolicyTests {
    private func input(_ json: String) -> JSONObject { try! JSONObject(validating: Array(json.utf8)) }

    private func decide(_ policy: ApprovalPolicy, _ tool: String, _ json: String = "{}") -> ApprovalPolicy.Decision {
        policy.decide(tool: tool, input: input(json), workingDirectory: "/p")
    }

    private func asks(_ decision: ApprovalPolicy.Decision) -> CallScope? {
        if case .ask(let approval) = decision { return approval.scope }
        return nil
    }

    @Test func `by default commands, writes, edits and job input ask; the rest runs`() {
        let policy = ApprovalPolicy()
        #expect(asks(decide(policy, "bash", #"{"command":"git status"}"#)) == .command(CommandWords("git status")))
        #expect(asks(decide(policy, "write", #"{"path":"src/a.swift","content":""}"#)) == .file("/p/src/a.swift"))
        #expect(asks(decide(policy, "edit", #"{"path":"/x/b.swift"}"#)) == .file("/x/b.swift"))
        #expect(asks(decide(policy, "job", #"{"job":"3","action":"input","text":"y"}"#)) == .tool("job"))
        for (tool, json) in [
            ("read", #"{"path":"a"}"#), ("job", #"{"job":"3","action":"status"}"#), ("job_stop", "{}"), ("wait", "{}"),
            ("search_catalog", "{}"), ("skill", "{}"), ("narrow_sandbox", "{}")
        ] {
            #expect(decide(policy, tool, json) == .run, "\(tool)")
        }
    }

    @Test func `the person's lists win over the defaults, and patterns cover MCP tools`() {
        let policy = ApprovalPolicy(
            section: ApprovalsSection(allow: ["bash", "mcp__docs__*"], ask: ["read", "mcp__x__look"]))
        #expect(decide(policy, "bash", #"{"command":"rm x"}"#) == .run)
        #expect(asks(decide(policy, "read", #"{"path":"a"}"#)) == .tool("read"))
        #expect(decide(policy, "mcp__docs__search") == .runWithoutServerQuestion)
        #expect(asks(decide(policy, "mcp__x__look")) == .tool("mcp__x__look"))
        #expect(decide(policy, "mcp__y__other") == .run, "otherwise an MCP tool's own rule applies (0153)")
    }

    @Test func `default allow runs what no list names`() {
        let policy = ApprovalPolicy(section: ApprovalsSection(defaultMode: .allow, ask: ["write"]))
        #expect(decide(policy, "bash", #"{"command":"ls"}"#) == .run)
        #expect(asks(decide(policy, "write", #"{"path":"a"}"#)) != nil)
    }

    @Test func `--yes allows everything; --ask-always asks even what the config allows`() {
        let section = ApprovalsSection(defaultMode: .allow, allow: ["bash"], ask: ["read"])
        let yes = ApprovalPolicy(section: section, flag: .yes)
        #expect(decide(yes, "read", #"{"path":"a"}"#) == .run && decide(yes, "bash", #"{"command":"rm x"}"#) == .run)
        let always = ApprovalPolicy(section: section, flag: .askAlways)
        #expect(asks(decide(always, "bash", #"{"command":"ls"}"#)) != nil)
        #expect(asks(decide(always, "read", #"{"path":"a"}"#)) != nil)
        #expect(decide(always, "wait") == .run, "read-only tools stay exempt unless listed")
    }
}
