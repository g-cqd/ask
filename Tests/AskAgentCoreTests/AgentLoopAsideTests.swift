import AemiIO
import AskAI
import Foundation
import System
import Testing

@testable import AskAgentCore

/// `/btw` (roadmap 0194): one request over the conversation so far and the question, with the tools' definitions but none run, kept out
/// of the session; its tokens count, and the context's size stays the conversation's.
@Suite("An aside is answered over the conversation and kept out of it")
struct AgentLoopAsideTests {
    private let directory = FileManager.default.temporaryDirectory.appending(path: "ask-aside-\(UUID().uuidString)")

    private struct Echo: ArgumentTool {
        struct Arguments: Decodable, Sendable { let text: String }
        let definition = ToolDefinition(name: "echo", description: "Echo.") { ToolProperty.string("text") }
        func run(_ arguments: Arguments, in context: ToolContext) async throws(ToolFailure) -> ToolOutput {
            ToolOutput(arguments.text)
        }
    }

    @Test
    func
        `the request is the conversation, then the question and the instruction; the answer is its text; nothing is recorded`()
        async throws
    {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = SessionRecorder(
            try SessionFile.create(at: .init(directory.appending(path: "s.jsonl").path), durability: .none)
        )
        let provider = ScriptedProvider([
            .call(id: "t1", name: "echo", input: #"{"text":"hi"}"#), .reply("Done."), .reply("Because of Y.")
        ])
        let loop = AgentLoop(
            provider: provider,
            tools: try ToolRegistry([Echo()]),
            settings: AgentSettings(model: "m", maximumTokens: 64, systemPrompt: [], maximumTurns: 4),
            context: ToolContext(workingDirectory: directory.path)
        )
        try await loop.run("Do X", in: file) { _ in }
        let recorded = file.tree.entries.count
        let (answer, _) = try await loop.aside("why X?", over: file.tree)
        #expect(answer == "Because of Y.")
        #expect(file.tree.entries.count == recorded, "the aside is not part of the conversation")
        let sent = try #require(provider.requests.last)
        #expect(sent.tools.map(\.name) == ["echo"], "a history of tool calls needs the definitions")
        #expect(sent.messages.first?.blocks.contains(.text("Do X")) == true)
        let asked = try #require(sent.messages.last?.blocks.last)
        guard case .text(let text) = asked else {
            Issue.record("the question is text")
            return
        }
        #expect(text.hasPrefix("why X?") && text.hasSuffix(AgentLoop.asideInstruction))
    }

    @Test func `before a session there is no conversation, and the question goes alone`() async throws {
        let provider = ScriptedProvider([.reply("Hello.")])
        let loop = AgentLoop(
            provider: provider,
            tools: try ToolRegistry([]),
            settings: AgentSettings(model: "m", maximumTokens: 64, systemPrompt: [], maximumTurns: 4),
            context: ToolContext(workingDirectory: "/tmp")
        )
        #expect(try await loop.aside("hi?", over: nil).answer == "Hello.")
        #expect(provider.requests.last?.messages.count == 1)
    }

    @Test func `its tokens add to the totals, and the context's size stays the conversation's`() {
        var totals = UsageTotals()
        totals.add(TokenUsage(input: 100, output: 10))
        let context = totals.contextTokens
        totals.addBeside(TokenUsage(input: 120, output: 5))
        #expect(totals.contextTokens == context)
        #expect(totals.input == 220 && totals.output == 15)
    }
}
