import AemiIO
import AskAI
import Darwin
import Foundation
import System
import Testing

@testable import AskAgentCore

@Suite("Queued input enters only at safe boundaries and is persisted exactly once")
struct SteeringTests {
    private func session() throws -> SessionRecorder {
        let path = FileManager.default.temporaryDirectory.appending(path: "ask-steering-\(UUID().uuidString).jsonl")
            .path
        return SessionRecorder(try SessionFile.create(at: .init(path), durability: .none))
    }

    private func loop(_ provider: ScriptedProvider, turns: Int = 12) throws -> AgentLoop {
        AgentLoop(
            provider: provider, tools: try ToolRegistry([]),
            settings: AgentSettings(model: "m", maximumTokens: 1_024, systemPrompt: [], maximumTurns: turns),
            context: ToolContext(workingDirectory: "/tmp"))
    }

    private func prompts(_ session: SessionRecorder) -> [String] {
        session.tree.entries.compactMap {
            if case .user(let text) = $0.payload { return text }
            return nil
        }
    }

    @Test func `steering waits for every tool result before entering the next request`() async throws {
        let file = try session()
        let provider = ScriptedProvider([
            .calls([("a", "unknown", "{}"), ("b", "unknown", "{}")]), .reply("Done.")
        ])
        let input = PromptQueue()
        try await loop(provider)
            .run("Start", in: file, input: input) { event in
                if case .model(.textDelta) = event { return }
                if case .toolStarted(id: "a", name: _, input: _) = event {
                    input.append(QueuedPrompt(id: 1, text: "Change direction"))
                }
            }
        #expect(prompts(file) == ["Start", "Change direction"])
        #expect(
            file.tree.entries.map(\.payload).dropFirst(2).prefix(2)
                .allSatisfy {
                    if case .toolResult = $0 { return true }
                    return false
                })
        #expect(
            provider.requests.last?.messages.last
                == ModelMessage(
                    role: .user,
                    blocks: [
                        .toolResult(id: "a", content: "No tool is named unknown. Available: .", isError: true),
                        .toolResult(id: "b", content: "No tool is named unknown. Available: .", isError: true),
                        .text("Change direction")
                    ]))
        #expect(input.remaining.isEmpty)
    }

    @Test func `follow-ups wait through tools and pauses while steering overtakes them`() async throws {
        let file = try session()
        let provider = ScriptedProvider([
            .call(id: "a", name: "unknown", input: "{}"), .pause("Still working"), .reply("First done"),
            .reply("Steered"), .reply("Followed up")
        ])
        let input = PromptQueue()
        input.append(QueuedPrompt(id: 1, text: "Later", delivery: .followUp))
        var added = false
        try await loop(provider)
            .run("Start", in: file, input: input) { event in
                if case .responded(let response) = event, response.stopReason == .endTurn, !added {
                    added = true
                    input.append(QueuedPrompt(id: 2, text: "Now"))
                }
            }
        #expect(prompts(file) == ["Start", "Now", "Later"])
        #expect(provider.requests.count == 5)
        #expect(input.remaining.isEmpty)
    }

    @Test func `one steering message enters per turn in FIFO order`() async throws {
        let file = try session()
        let provider = ScriptedProvider([.reply("a"), .reply("b"), .reply("c")])
        let input = PromptQueue()
        input.append(QueuedPrompt(id: 1, text: "One"))
        input.append(QueuedPrompt(id: 2, text: "Two"))
        try await loop(provider).run("Start", in: file, input: input) { _ in }
        #expect(prompts(file) == ["Start", "One", "Two"])
        #expect(provider.requests.count == 3)
    }

    @Test func `provider failure and the turn limit leave unsent messages queued`() async throws {
        let file = try session()
        let input = PromptQueue()
        let later = QueuedPrompt(id: 1, text: "Later", delivery: .followUp)
        input.append(later)
        await #expect(throws: AgentError.provider("scripted failure")) {
            try await loop(ScriptedProvider([.failure])).run("Start", in: file, input: input) { _ in }
        }
        #expect(input.remaining == [later])
        await #expect(throws: AgentError.turnLimit(1)) {
            try await loop(ScriptedProvider([.pause("wait")]), turns: 1).run("Again", in: file, input: input) { _ in }
        }
        #expect(input.remaining == [later])
        #expect(prompts(file) == ["Start", "Again"])
    }

    @Test func `the last allowed turn cannot swallow a queued prompt with no turn left to answer it`() async throws {
        let file = try session()
        let input = PromptQueue()
        let pending = QueuedPrompt(id: 1, text: "Unsent")
        input.append(pending)
        await #expect(throws: AgentError.turnLimit(1)) {
            try await loop(ScriptedProvider([.reply("Done")]), turns: 1).run("Start", in: file, input: input) { _ in }
        }
        #expect(input.remaining == [pending])
        #expect(prompts(file) == ["Start"])
    }

    @Test func `a queued prompt that fails to persist stays queued and is never acknowledged`() async throws {
        let path = FileManager.default.temporaryDirectory.appending(
            path: "ask-steering-write-\(UUID().uuidString).jsonl")
        _ = try SessionFile.create(at: FilePath(path.path), durability: .none)
        var writes = 0
        let file = SessionRecorder(
            try SessionFile.open(at: FilePath(path.path), durability: .none) {
                bytes, descriptor throws(SessionFileError) in
                writes += 1
                if writes == 3 { throw .io(.write, errno: EIO) }
                try SessionFileIO.writeAll(bytes, to: descriptor)
            })
        let input = PromptQueue()
        let pending = QueuedPrompt(id: 1, text: "Unsent")
        input.append(pending)
        var accepted: [QueuedPrompt] = []
        await #expect(throws: AgentError.session(.io(.write, errno: EIO))) {
            try await loop(ScriptedProvider([.reply("Done")]))
                .run("Start", in: file, input: input) {
                    if case .promptAccepted(let prompt) = $0 { accepted.append(prompt) }
                }
        }
        #expect(accepted.isEmpty)
        #expect(input.remaining == [pending])
        #expect(prompts(file) == ["Start"])
    }

    @Test func `cancellation at a boundary does not consume a queued message`() async throws {
        let file = try session()
        let input = PromptQueue()
        let pending = QueuedPrompt(id: 1, text: "Unsent")
        input.append(pending)
        // A child task isolates cancellation from the test's own task.
        async let run: Void = {
            await #expect(throws: AgentError.cancelled) {
                try await loop(ScriptedProvider([.reply("Done")]))
                    .run("Start", in: file, input: input) { event in
                        if case .responded = event { withUnsafeCurrentTask { $0?.cancel() } }
                    }
            }
        }()
        await run
        #expect(input.remaining == [pending])
        #expect(prompts(file) == ["Start"])
    }
}
