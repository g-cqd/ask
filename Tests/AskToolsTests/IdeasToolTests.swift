import AskAI
import AskAgentCore
import Foundation
import Testing

@testable import AskTools

/// The notes, through `tasks` (ADR-0141, ADR-0161): the model reads and marks the person's notes, in batches, and says which task
/// one became.
@Suite
struct IdeasToolTests {
    private let board = IdeaBoard()
    private let tasks = TaskBoard()
    private let context = ToolContext(workingDirectory: "/tmp")

    init() throws {
        let directory = NSTemporaryDirectory() + "ask-notes-tool-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        try board.attach(sessionPath: directory + "/s.jsonl", format: .plain, keyring: nil, scope: .session)
        try tasks.attach(sessionPath: directory + "/s.jsonl", format: .plain, keyring: nil, scope: .session)
        try board.change { $0.adding("fold the sidebar\nwhen narrow", at: 0) }
        try board.change { $0.adding(String(repeating: "long ", count: 40), at: 60) }
        try tasks.change { $0.adding(title: "fold it") }
    }

    private func call(_ json: String) async throws -> ToolOutput {
        let named = #"{"list":"notes","# + json.dropFirst()
        return await TasksTool(board: tasks, notes: board)
            .run(try JSONObject(validating: Array(named.utf8)), in: context)
    }

    @Test
    func `a listing counts the new ones and cuts long notes, and a read by id shows one whole, once`() async throws {
        let listed = try await call(#"{"read":{}}"#).content
        #expect(
            listed.hasPrefix("2 new.\nn1 [new] ") && listed.contains("fold the sidebar when narrow")
                && listed.contains("…")
        )
        let whole = try await call(#"{"read":{"ids":"n1"}}"#).content
        #expect(
            whole.hasSuffix("\nfold the sidebar\nwhen narrow")
                && whole.components(separatedBy: "fold the sidebar").count == 2
        )
    }

    @Test
    func `marks are batched, linked to the task a note became, and safe to repeat`() async throws {
        let batch = #"{"changes":[{"ids":"n1","state":"fulfilled","task":"t1"},{"ids":"n2","state":"dismissed"}]}"#
        #expect(try await call(batch).content == "fulfilled n1 · dismissed n2 · linked n1")
        let again = try await call(batch)
        #expect(again.content == "already so: n1–n2 (2)")
        #expect(try board.current()?.idea(1)?.tasks == [1])
        #expect(try await call(#"{"read":{"view":"all"}}"#).content.contains("→ t1"))
    }

    @Test
    func `it cannot write a note, link a task that is not there, or name one that is not`() async throws {
        let write = try await call(#"{"changes":[{"ids":"n1","state":"new"}]}"#)
        #expect(write.isError && write.content.contains("acknowledged, fulfilled or dismissed"))
        let text = try await call(#"{"changes":[{"ids":"n1","state":"fulfilled","text":"mine now"}]}"#)
        #expect(text.isError && text.content.contains("takes no \"text\""))
        let task = try await call(#"{"changes":[{"ids":"n1","state":"fulfilled","task":"t9"}]}"#)
        #expect(task.isError && task.content.contains("there is no task t9"))
        let note = try await call(#"{"changes":[{"ids":"n1 n7","state":"acknowledged"}]}"#)
        #expect(note.isError && note.content.contains("there is no note n7"))
        #expect(try board.current()?.ideas.map(\.state) == [.new, .new])
    }

    @Test
    func `before a session there are no notes, and the tool says so`() async throws {
        let output = await TasksTool(board: TaskBoard())
            .run(try JSONObject(validating: Array(#"{"list":"notes","read":{}}"#.utf8)), in: context)
        #expect(output == .error("No notes are open for this session."))
    }

    /// ADR-0161: `list` says which; a call that leaves it out and can only mean the notes is not refused for it.
    @Test(arguments: [
        #"{"read":{"ids":"n1"}}"#, #"{"read":{"view":"new"}}"#, #"{"changes":[{"ids":"n1","state":"acknowledged"}]}"#,
        #"{"changes":[{"op":"state","ids":"n1","state":"acknowledged"}]}"#
    ])
    func `a note's id or the view only notes have means the notes, without list`(_ json: String) async throws {
        let tool = TasksTool(board: tasks, notes: board)
        let output = await tool.run(try JSONObject(validating: Array(json.utf8)), in: context)
        #expect(!output.isError && (output.content.contains("n1")), "\(output.content)")
    }

    @Test
    func `one call is on one list, and a list that is neither is said`() async throws {
        let tool = TasksTool(board: tasks, notes: board)
        func run(_ json: String) async throws -> ToolOutput {
            await tool.run(try JSONObject(validating: Array(json.utf8)), in: context)
        }
        #expect(try await run(#"{"list":"tasks","read":{}}"#).content.contains("t1"))
        #expect(try await run(#"{"read":{}}"#).content.contains("t1"))
        let neither = try await run(#"{"list":"ideas","read":{}}"#)
        #expect(neither.isError && neither.content.contains("list is tasks or notes"))
        let written = try await run(#"{"list":"notes","changes":[{"op":"add","title":"mine"}]}"#)
        #expect(written.isError && written.content.contains("the person's to write"))
        let wrong = try await run(#"{"list":"tasks","read":{"view":"new"}}"#)
        #expect(wrong.isError && wrong.content.contains("open, done, all or summary"))
        #expect(try board.current()?.ideas.count == 2)
    }
}
