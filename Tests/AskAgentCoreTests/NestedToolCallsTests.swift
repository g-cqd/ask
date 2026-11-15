import AemiIO
import AskAI
import Foundation
import Synchronization
import System
import Testing

@testable import AskAgentCore

/// The calls a tool makes for the model (ADR-0156: a codemode script's): each is a tool call of the loop's, through its hooks
/// and its sandbox, and none is a side door. What is not asked again is the person: the script was approved as a whole.
@Suite("A tool that runs a script calls the others through the loop")
struct NestedToolCallsTests {
    private let directory = FileManager.default.temporaryDirectory.appending(path: "ask-nested-\(UUID().uuidString)")

    private struct Hook: AgentHook {
        var name = "Policy"
        var decide: @Sendable (ToolInvocation) -> ToolCallDecision = { _ in .allow }
        var after: @Sendable (ToolInvocation, ToolOutput) -> ToolResultDecision = { ToolResultDecision(output: $1) }
        var approve: @Sendable (ToolCallApproval) -> ApprovalDecision = { _ in .ask }

        func toolCall(_ call: ToolInvocation) async -> ToolCallDecision { decide(call) }
        func toolResultDecision(_ call: ToolInvocation, _ output: ToolOutput) async -> ToolResultDecision {
            after(call, output)
        }
        func approval(_ request: ToolCallApproval) async -> ApprovalDecision { approve(request) }
    }

    private struct Outcome {
        let result: String
        let events: [AgentEvent]
        let payloads: [SessionPayload]
        let asked: Int
        let bash: Int
        let read: Int
        let offered: [String]?
    }

    /// One run where the model calls `script` with `calls`; `gated` puts the person's gate in, who is counted and says yes.
    private func run(_ calls: String, hooks: [any AgentHook] = [], gated: Bool = false, together: Bool = false)
        async throws -> Outcome
    {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = directory.appending(path: "\(UUID().uuidString).jsonl").path
        let file = SessionRecorder(try SessionFile.create(at: .init(path), durability: .none))
        let (script, bash, read) = (ScriptingTool(), CountingTool("bash"), CountingTool("read"))
        let asked = Mutex(0)
        let gate = ToolCallGate(policy: ApprovalPolicy()) { _ in
            asked.withLock { $0 += 1 }
            return true
        }
        let input = #"{"calls":[\#(calls)],"together":\#(together)}"#
        let loop = AgentLoop(
            provider: ScriptedProvider([.call(id: "t1", name: "script", input: input), .reply("Done.")]),
            tools: try ToolRegistry([script, bash, read]),
            settings: AgentSettings(model: "m", maximumTokens: 64, systemPrompt: [], maximumTurns: 4),
            context: ToolContext(workingDirectory: directory.path, callGate: gated ? gate : nil),
            hooks: hooks
        )
        let events = Mutex<[AgentEvent]>([])
        try await loop.run("Go", in: file) { event in events.withLock { $0.append(event) } }
        let payloads = file.tree.entries.map(\.payload)
        var result = ""
        for case .toolResult(_, let content, _, _, _) in payloads { result = content }
        return Outcome(
            result: result,
            events: events.withLock { $0 },
            payloads: payloads,
            asked: asked.withLock { $0 },
            bash: bash.count,
            read: read.count,
            offered: script.offered
        )
    }

    @Test func `it is offered the run's other tools, and what it calls runs`() async throws {
        let outcome = try await run(#""read","bash","read""#)
        #expect(outcome.offered == ["bash", "read"], "every tool but itself")
        #expect(outcome.result == "ok: ran\nok: ran\nok: ran")
        #expect(outcome.read == 2 && outcome.bash == 1)
    }

    @Test func `only the call the model made is an event and a record`() async throws {
        let outcome = try await run(#""read","bash""#)
        let started = outcome.events.compactMap { event -> String? in
            if case .toolStarted(_, let name, _) = event { name } else { nil }
        }
        #expect(started == ["script"])
        let results = outcome.payloads.filter { if case .toolResult = $0 { true } else { false } }
        #expect(results.count == 1)
    }

    @Test func `it cannot call itself, and a name nobody has is the registry's error`() async throws {
        let outcome = try await run(#""script","nope""#)
        #expect(
            outcome.result.hasPrefix("error: A script cannot call script.\nerror: No tool is named nope. Available: ")
        )
    }

    @Test func `a hook that blocks a tool blocks it inside a script too, and one that rewrites or adds is heard`()
        async throws
    {
        let blocking = Hook(decide: { $0.name == "bash" ? .block(reason: "no commands here") : .allow })
        let blocked = try await run(#""bash","read""#, hooks: [blocking])
        #expect(blocked.result == "error: This call was blocked before it ran: no commands here\nok: ran")
        #expect(blocked.bash == 0 && blocked.read == 1)
        let adding = Hook(after: { call, output in
            call.name == "read"
                ? ToolResultDecision(output: ToolOutput(output.content.uppercased()), context: "lint: 2 warnings")
                : .init(output: output)
        })
        let added = try await run(#""read""#, hooks: [adding])
        #expect(added.result == "ok: RAN\n[hook Policy] lint: 2 warnings")
    }

    @Test func `the person is not asked again for what a script calls`() async throws {
        // `bash` asks when the model calls it; here the script was the call, and `script` is not a tool that asks.
        let outcome = try await run(#""bash","bash""#, gated: true)
        #expect(outcome.asked == 0 && outcome.bash == 2)
        #expect(outcome.result == "ok: ran\nok: ran")
    }

    @Test func `a hook that refuses an approval still refuses it inside a script, and is named`() async throws {
        let refusing = Hook(approve: { $0.tool == "bash" ? .refuse("not on Fridays") : .ask })
        let outcome = try await run(#""bash","read""#, hooks: [refusing], gated: true)
        #expect(outcome.result == "error: The hook Policy refused this call: not on Fridays\nok: ran")
        #expect(outcome.bash == 0 && outcome.asked == 0)
        #expect(outcome.events.contains(.hookAnswered(hook: "Policy", tool: "bash", approved: false)))
    }

    @Test func `calls made at once all run`() async throws {
        let names = Array(repeating: #""read""#, count: 40).joined(separator: ",")
        let outcome = try await run(names, together: true)
        #expect(outcome.read == 40)
        #expect(outcome.result.split(separator: "\n").count == 40)
    }

    @Test func `inside a script nobody widens the sandbox, and no server asks its own question`() {
        let gate = ToolCallGate(policy: ApprovalPolicy()) { _ in false }
        let context = ToolContext(
            workingDirectory: "/work",
            approve: { _ in true },
            destructiveApprover: { _ in true },
            callGate: gate
        )
        let inside = context.withinScript()
        #expect(inside.approve == nil && inside.destructiveApprover == nil)
        #expect(inside.callGate != nil, "the policy and the hooks' answers still apply")
        #expect(ToolContext(workingDirectory: "/work").withinScript().callGate == nil, "no gate stays no gate")
    }
}
