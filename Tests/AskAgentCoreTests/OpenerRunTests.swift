internal import Testing

@testable import AskAgentCore

/// ADR-0148: a command asks before it runs, unless the person allowed it always or runs everything unasked.
@Suite("An opener's command asks first, unless it was allowed")
struct OpenerRunTests {
    private let rule = OpenerRule(kind: .file, command: ["code", "{path}"])

    @Test func `it asks by default, and offers to remember`() {
        #expect(OpenerRun.decide(rule, policy: ApprovalPolicy(), grants: OpenerGrants()) == .ask(remembers: true))
    }

    @Test func `allowed always, it runs, until the command changes`() {
        var grants = OpenerGrants()
        grants.allow(rule)
        #expect(OpenerRun.decide(rule, policy: ApprovalPolicy(), grants: grants) == .run)
        var edited = rule
        edited.command = ["rm", "{path}"]
        #expect(OpenerRun.decide(edited, policy: ApprovalPolicy(), grants: grants) == .ask(remembers: true))
    }

    @Test func `under yes, or approvals that allow by default, it runs unasked`() {
        #expect(OpenerRun.decide(rule, policy: ApprovalPolicy(flag: .yes), grants: OpenerGrants()) == .run)
        let allowing = ApprovalPolicy(section: ApprovalsSection(defaultMode: .allow))
        #expect(OpenerRun.decide(rule, policy: allowing, grants: OpenerGrants()) == .run)
    }

    @Test func `asked about everything, it asks every time and remembers nothing`() {
        var grants = OpenerGrants()
        grants.allow(rule)
        let always = ApprovalPolicy(section: ApprovalsSection(defaultMode: .allow), flag: .askAlways)
        #expect(OpenerRun.decide(rule, policy: always, grants: grants) == .ask(remembers: false))
    }

    @Test func `the arguments are shown one line, each kept apart`() {
        #expect(OpenerRun.shown(["code", "--goto", "/a/b.swift:12"]) == "code --goto /a/b.swift:12")
        #expect(OpenerRun.shown(["open", "/a/My Notes/b c.md", ""]) == "open '/a/My Notes/b c.md' ''")
        #expect(OpenerRun.shown(["t", "it's"]) == #"t 'it'\''s'"#)
    }
}
