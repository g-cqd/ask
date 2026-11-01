import AskAI
import AskAgentCore
import Foundation
import Testing

@testable import AskTools

/// The `ideas` tool of ADR-0141: the model reads and marks the person's ideas, in batches, and says which task one became.
@Suite
struct IdeasToolTests {
    private let board = IdeaBoard()
    private let tasks = TaskBoard()
    private let context = ToolContext(workingDirectory: "/tmp")

    init() throws {
        let directory = NSTemporaryDirectory() + "ask-ideas-tool-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        try board.attach(sessionPath: directory + "/s.jsonl", format: .plain, keyring: nil, scope: .session)
        try tasks.attach(sessionPath: directory + "/s.jsonl", format: .plain, keyring: nil, scope: .session)
        try board.change { $0.adding("fold the sidebar\nwhen narrow", at: 0) }
        try board.change { $0.adding(String(repeating: "long ", count: 40), at: 60) }
        try tasks.change { $0.adding(title: "fold it") }
    }

    private func call(_ json: String) async throws -> ToolOutput {
        await IdeasTool(board: board, tasks: tasks).run(try JSONObject(validating: Array(json.utf8)), in: context)
    }

    @Test
    func `a listing counts the new ones and cuts long ideas, and a read by id shows one whole, once`() async throws {
        let listed = try await call(#"{"read":{}}"#).content
        #expect(
            listed.hasPrefix("2 new.\ni1 [new] ") && listed.contains("fold the sidebar when narrow")
                && listed.contains("…")
        )
        let whole = try await call(#"{"read":{"ids":"i1"}}"#).content
        #expect(
            whole.hasSuffix("\nfold the sidebar\nwhen narrow")
                && whole.components(separatedBy: "fold the sidebar").count == 2
        )
    }

    @Test
    func `marks are batched, linked to the task an idea became, and safe to repeat`() async throws {
        let batch = #"{"changes":[{"ids":"i1","state":"fulfilled","task":"t1"},{"ids":"i2","state":"dismissed"}]}"#
        #expect(try await call(batch).content == "fulfilled i1 · dismissed i2 · linked i1")
        let again = try await call(batch)
        #expect(again.content == "already so: i1–i2 (2)")
        #expect(try board.current()?.idea(1)?.tasks == [1])
        #expect(try await call(#"{"read":{"view":"all"}}"#).content.contains("→ t1"))
    }

    @Test
    func `it cannot write an idea, link a task that is not there, or name one that is not`() async throws {
        let write = try await call(#"{"changes":[{"ids":"i1","state":"new"}]}"#)
        #expect(write.isError && write.content.contains("acknowledged, fulfilled or dismissed"))
        let text = try await call(#"{"changes":[{"ids":"i1","state":"fulfilled","text":"mine now"}]}"#)
        #expect(text.isError && text.content.contains("takes no \"text\""))
        let task = try await call(#"{"changes":[{"ids":"i1","state":"fulfilled","task":"t9"}]}"#)
        #expect(task.isError && task.content.contains("there is no task t9"))
        let idea = try await call(#"{"changes":[{"ids":"i1 i7","state":"acknowledged"}]}"#)
        #expect(idea.isError && idea.content.contains("there is no idea i7"))
        #expect(try board.current()?.ideas.map(\.state) == [.new, .new])
    }

    @Test
    func `before a session there are no ideas, and the tool says so`() async throws {
        let output = await IdeasTool(board: IdeaBoard())
            .run(try JSONObject(validating: Array(#"{"read":{}}"#.utf8)), in: context)
        #expect(output.isError)
    }
}
