import AemiIO
import AskAI
import Foundation
import Synchronization
import System
import Testing

@testable import AskAgentCore

/// A hook may answer a call's approval in the person's place, either way (roadmap 0192, ADR-0143): the first answer other than `ask`
/// wins, the person is asked only when every hook says `ask`, and the run says which hook answered. Nothing is asked where nothing would
/// be: without a gate, as in `ask -p`, or for a call the policy runs.
@Suite("Hooks answer approvals in the person's place, and the first answer wins")
struct AgentHookApprovalTests {
    private let directory = FileManager.default.temporaryDirectory.appending(path: "ask-approval-\(UUID().uuidString)")

    /// Answers every approval with `answer`, and counts what it was asked.
    private final class Approver: AgentHook {
        let name: String
        let answer: ApprovalDecision
        private let seen = Mutex<[String]>([])
        var asked: [String] { seen.withLock { $0 } }
        init(_ name: String, _ answer: ApprovalDecision) {
            self.name = name
            self.answer = answer
        }

        func approval(_ request: ToolCallApproval) async -> ApprovalDecision {
            seen.withLock { $0.append(request.tool) }
            return answer
        }
    }

    /// The person: says `answer`, and counts the questions.
    private final class Person: Sendable {
        let asked = Mutex(0)
        let answer: Bool
        init(_ answer: Bool) { self.answer = answer }
        var gate: ToolCallGate {
            ToolCallGate(policy: ApprovalPolicy()) { [self] _ in
                asked.withLock { $0 += 1 }
                return answer
            }
        }
    }

    private struct Outcome {
        let ran: Int
        let result: (content: String, isError: Bool)?
        let answered: [AgentEvent]
    }

    private func run(_ hooks: [any AgentHook], person: Person?, tool name: String = "bash") async throws -> Outcome {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = SessionRecorder(
            try SessionFile.create(at: .init(directory.appending(path: "s.jsonl").path), durability: .none)
        )
        let tool = CountingTool(name)
        let provider = ScriptedProvider([
            .call(id: "t1", name: name, input: #"{"command":"rm -rf build"}"#), .reply("Done.")
        ])
        let loop = AgentLoop(
            provider: provider,
            tools: try ToolRegistry([tool]),
            settings: AgentSettings(model: "m", maximumTokens: 64, systemPrompt: [], maximumTurns: 4),
            context: ToolContext(workingDirectory: directory.path, callGate: person?.gate),
            hooks: hooks
        )
        let events = Mutex<[AgentEvent]>([])
        try await loop.run("Go", in: file) { event in events.withLock { $0.append(event) } }
        var result: (String, Bool)?
        for case .toolResult(_, let content, let isError, _, _) in file.tree.entries.map(\.payload) {
            result = (content, isError)
        }
        let answered = events.withLock { $0 }.filter { if case .hookAnswered = $0 { true } else { false } }
        return Outcome(ran: tool.count, result: result, answered: answered)
    }

    @Test func `a hook that approves runs the call without asking the person, and is named`() async throws {
        let person = Person(false)
        let outcome = try await run([Approver("Policy", .approve)], person: person)
        #expect(outcome.ran == 1 && person.asked.withLock { $0 } == 0)
        #expect(outcome.answered == [.hookAnswered(hook: "Policy", tool: "bash", approved: true)])
    }

    @Test func `a hook that refuses stops the call, and the model is told which hook and why`() async throws {
        let person = Person(true)
        let outcome = try await run([Approver("Policy", .refuse("no deletions on Fridays"))], person: person)
        #expect(outcome.ran == 0 && person.asked.withLock { $0 } == 0)
        #expect(outcome.result?.isError == true)
        #expect(outcome.result?.content == "The hook Policy refused this call: no deletions on Fridays")
        #expect(outcome.answered == [.hookAnswered(hook: "Policy", tool: "bash", approved: false)])
    }

    @Test func `when every hook says ask, the person decides`() async throws {
        let person = Person(true)
        let outcome = try await run([Approver("A", .ask), Approver("B", .ask)], person: person)
        #expect(outcome.ran == 1 && person.asked.withLock { $0 } == 1 && outcome.answered.isEmpty)
    }

    @Test func `the first answer other than ask wins, and later hooks are not asked`() async throws {
        let first = Approver("A", .ask)
        let second = Approver("B", .refuse("no"))
        let third = Approver("C", .approve)
        let outcome = try await run([first, second, third], person: Person(true))
        #expect(outcome.ran == 0 && first.asked == ["bash"] && second.asked == ["bash"] && third.asked.isEmpty)
    }

    @Test func `without a gate, as in ask -p, no hook is asked`() async throws {
        let hook = Approver("A", .refuse("no"))
        let outcome = try await run([hook], person: nil)
        #expect(outcome.ran == 1 && hook.asked.isEmpty)
    }

    @Test func `a call the policy runs unasked asks no hook`() async throws {
        let hook = Approver("A", .refuse("no"))
        let outcome = try await run([hook], person: Person(false), tool: "read")
        #expect(outcome.ran == 1 && hook.asked.isEmpty)
    }
}
