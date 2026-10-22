internal import AskAI
internal import Foundation
internal import Testing

@testable import AskAgentCore

struct AgentThinkingTests {
    /// An inert tool result: this suite checks request propagation, not text processing or process execution.
    private struct FixedReply: Tool {
        let definition: ToolDefinition
        init() throws {
            definition = ToolDefinition(
                name: "fixture", description: "Return the fixture result.",
                inputSchema: try JSONObject(validating: Array(#"{"type":"object"}"#.utf8)))
        }
        func run(_ input: JSONObject, in context: ToolContext) async -> ToolOutput { ToolOutput("X") }
    }

    private let harness = CompactionHarness()

    private func loop(_ provider: ScriptedProvider, control: ThinkingControl?, compactAt: Int? = nil) throws
        -> AgentLoop
    {
        AgentLoop(
            provider: provider, tools: try ToolRegistry([FixedReply()]),
            settings: AgentSettings(
                model: "m", maximumTokens: 4096, systemPrompt: [], maximumTurns: 8, compactAtTokens: compactAt,
                keepRecentBytes: 1, thinking: control),
            context: ToolContext(workingDirectory: harness.directory.path))
    }

    @Test func `an unset policy leaves normal requests unset`() async throws {
        let file = try harness.newFile()
        defer { try? FileManager.default.removeItem(at: harness.directory) }
        let provider = ScriptedProvider([.reply("ok")])
        try await loop(provider, control: nil).run("hello", in: file) { _ in }
        try #require(provider.requests.count == 1)
        #expect(provider.requests[0].thinking == nil)
    }

    @Test func `every request in a tool loop retains the selected thinking control`() async throws {
        let file = try harness.newFile()
        defer { try? FileManager.default.removeItem(at: harness.directory) }
        let provider = ScriptedProvider([.call(id: "t", name: "fixture", input: #"{"text":"x"}"#), .reply("X")])
        try await loop(provider, control: .effort(.high)).run("uppercase x", in: file) { _ in }
        try #require(provider.requests.count == 2)
        #expect(provider.requests.allSatisfy { $0.thinking == .effort(.high) })
        #expect(provider.requests[1].messages.last?.blocks.first == .toolResult(id: "t", content: "X", isError: false))
    }

    @Test func `the compaction request and the resumed request retain the selected control`() async throws {
        let file = try harness.newFile()
        defer { try? FileManager.default.removeItem(at: harness.directory) }
        let provider = ScriptedProvider([.sized("first", prompt: 150), .reply("SUMMARY"), .reply("second")])
        let agent = try loop(provider, control: .betweenTools, compactAt: 100)
        try await agent.run("one", in: file) { _ in }
        try await agent.run("two", in: file) { _ in }
        try #require(provider.requests.count == 3)
        #expect(provider.requests[1].messages.last?.blocks.last == .text(Compaction.instruction))
        #expect(provider.requests.allSatisfy { $0.thinking == .betweenTools })
    }

    @Test func `a replacement loop uses its new control without rewriting earlier session responses`() async throws {
        let file = try harness.newFile()
        defer { try? FileManager.default.removeItem(at: harness.directory) }
        let provider = ScriptedProvider([.reply("first"), .reply("second")])
        try await loop(provider, control: .budget(tokens: 3072, effort: nil)).run("one", in: file) { _ in }
        let firstResponse = file.tree.entries.last?.payload
        try await loop(provider, control: .disabled).run("two", in: file) { _ in }
        try #require(provider.requests.count == 2)
        #expect(provider.requests[0].thinking == .budget(tokens: 3072, effort: nil))
        #expect(provider.requests[1].thinking == .disabled)
        #expect(file.tree.entries[1].payload == firstResponse)
    }
}
