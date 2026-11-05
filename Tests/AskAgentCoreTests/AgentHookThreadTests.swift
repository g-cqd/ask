import AskAI
import Foundation
import Testing

@testable import AskAgentCore

/// The thread hook points (roadmap 0195, for 0192): `thread.start` may refuse a thread or rewrite its prompt; `thread.merge` may add to
/// its summary's instructions, and `thread.merged` may rewrite the summary its parent receives. Hooks chain in order, as elsewhere.
@Suite("Hooks see a thread start and merge")
struct AgentHookThreadTests {
    private struct Hook: AgentHook {
        let name: String
        var start: @Sendable (ThreadStart) -> ThreadStartDecision = { _ in .allow }
        var merge: @Sendable (ThreadMerge) -> ThreadMergeDecision = { _ in .allow }
        var merged: @Sendable (ThreadMerge, String) -> String = { $1 }
        func threadStart(_ start: ThreadStart) async -> ThreadStartDecision { self.start(start) }
        func threadMerge(_ merge: ThreadMerge) async -> ThreadMergeDecision { self.merge(merge) }
        func threadMerged(_ merge: ThreadMerge, summary: String) async -> String { merged(merge, summary) }
    }

    private func loop(_ hooks: [any AgentHook]) throws -> AgentLoop {
        AgentLoop(
            provider: ScriptedProvider([]),
            tools: try ToolRegistry([]),
            settings: AgentSettings(model: "m", maximumTokens: 64, systemPrompt: [], maximumTurns: 2),
            context: ToolContext(workingDirectory: FileManager.default.temporaryDirectory.path),
            hooks: hooks
        )
    }

    private let start = ThreadStart(name: "thread-1", parent: nil, prompt: "look into X")
    private let merge = ThreadMerge(name: "thread-1", parent: nil)

    @Test func `a start goes through as the hooks leave it, rewrites chaining in order`() async throws {
        let first = Hook(name: "a", start: { .rewrite($0.prompt + " carefully") })
        let second = Hook(name: "b", start: { .rewrite($0.prompt + ", then report") })
        #expect(try await loop([first, second]).startingThread(start) == .start("look into X carefully, then report"))
        #expect(try await loop([]).startingThread(start) == .start("look into X"))
    }

    @Test func `the first block refuses it, naming the hook and its reason`() async throws {
        let blocks = Hook(name: "guard", start: { _ in .block("no threads on Fridays") })
        let after = Hook(name: "never", start: { _ in .rewrite("unseen") })
        let outcome = try await loop([blocks, after]).startingThread(start)
        #expect(outcome == .refused("The hook guard refused this thread: no threads on Fridays"))
    }

    @Test func `a merge gathers the hooks' instructions, and blank ones are left out`() async throws {
        let one = Hook(name: "a", merge: { _ in .instructions("List the files.") })
        let blank = Hook(name: "b", merge: { _ in .instructions("  ") })
        let two = Hook(name: "c", merge: { _ in .instructions("Name the tests run.") })
        #expect(
            try await loop([one, blank, two]).mergeInstructions(merge) == ["List the files.", "Name the tests run."]
        )
    }

    @Test func `the summary goes through each hook in order`() async throws {
        let one = Hook(name: "a", merged: { $1 + " [checked]" })
        let two = Hook(name: "b", merged: { "\($0.name): " + $1 })
        #expect(try await loop([one, two]).mergedSummary(merge, "Done.") == "thread-1: Done. [checked]")
    }
}
