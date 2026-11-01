import AskAI
import AskAgentCore
import Foundation
import Testing

@testable import AskTools

/// The `tasks` tool of ADR-0141: batches, all or none, each change safe to repeat; strict input; lean definition.
@Suite
struct TasksToolTests {
    private let board = TaskBoard()
    private let context = ToolContext(workingDirectory: "/tmp")

    init() throws {
        let directory = NSTemporaryDirectory() + "ask-tasks-tool-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        try board.attach(sessionPath: directory + "/s.jsonl", format: .plain, keyring: nil, scope: .session)
    }

    private func call(_ json: String) async throws -> ToolOutput {
        await TasksTool(board: board) { 1_793_541_900 }.run(try JSONObject(validating: Array(json.utf8)), in: context)
    }

    @Test
    func `one call adds, links within itself, and reads, and the answer counts in runs`() async throws {
        let output = try await call(
            #"""
            {"changes":[{"op":"add","title":"parse","tags":"track-b"},{"op":"add","title":"ship","blocked_by":"@1"},
            {"op":"add","title":"tell","related":"@2"}],"read":{}}
            """#
        )
        #expect(!output.isError)
        #expect(
            output.content == """
                added t1–t3 (3)

                t1 [open] parse #track-b
                t2 [open, blocked by t1] ship
                t3 [open] tell · related t2
                """
        )
    }

    @Test
    func `repeating a call changes nothing, and says so`() async throws {
        let batch =
            #"{"changes":[{"op":"add","title":"a"},{"op":"add","title":"b"},{"op":"state","ids":"t1-t2","state":"done"}]}"#
        #expect(try await call(batch).content == "added t1–t2 (2) · done t1–t2 (2)")
        #expect(try await call(batch).content == "already so: t1–t2 (2)")
        #expect(try board.current()?.tasks.count == 2)
    }

    @Test
    func `a refused change refuses the call, naming it, and nothing of it is made`() async throws {
        let output = try await call(
            #"{"changes":[{"op":"add","title":"kept?"},{"op":"state","ids":"t9","state":"done"}]}"#
        )
        #expect(output.isError && output.content.contains("change 2 (state): there is no task t9."))
        #expect(try board.current()?.tasks.isEmpty == true)
    }

    @Test
    func `fields an operation does not take, unknown fields and malformed ids are refused before anything runs`()
        async throws
    {
        let wrongField = try await call(#"{"changes":[{"op":"state","ids":"t1","state":"done","title":"x"}]}"#)
        #expect(wrongField.isError && wrongField.content.contains("change 1: state takes no \"title\""))
        let unknown = try await call(#"{"changes":[],"filter":"x"}"#)
        #expect(unknown.isError && unknown.content.contains("takes no \"filter\""))
        let number = try await call(#"{"changes":[{"op":"remove","ids":"3"}]}"#)
        #expect(number.isError && number.content.contains("is not an id"))
        let state = try await call(#"{"changes":[{"op":"add","title":"x","state":"blocked"}]}"#)
        #expect(state.isError && state.content.contains("open, in_progress or done"))
        #expect(try await call(#"{}"#).isError)
    }

    @Test
    func `a read finds by words, shows ids in full, counts, and says what it left out`() async throws {
        _ = try await call(
            #"{"changes":[{"op":"add","title":"write the parser","detail":"recursive descent"},{"op":"add","title":"ship it"},{"op":"state","ids":"t2","state":"done"}]}"#
        )
        #expect(try await call(#"{"read":{"text":"descent"}}"#).content == "t1 [open] write the parser")
        #expect(try await call(#"{"read":{"ids":"t1"}}"#).content.hasSuffix("recursive descent"))
        #expect(try await call(#"{"read":{"view":"summary"}}"#).content == "2 tasks: 1 open, 0 in progress, 1 done")
        #expect(
            try await call(#"{"read":{"view":"all","limit":1}}"#).content
                .hasSuffix("(1 more; raise limit, or narrow the read.)")
        )
    }

    @Test
    func `before a session there is no list, and the tool says so`() async throws {
        let output = await TasksTool(board: TaskBoard())
            .run(try JSONObject(validating: Array(#"{"read":{}}"#.utf8)), in: context)
        #expect(output.isError)
    }

    @Test
    func `the definitions stay lean and are valid JSON`() throws {
        let tasks = TasksTool(board: TaskBoard()).definition
        let ideas = IdeasTool(board: IdeaBoard(), tasks: TaskBoard()).definition
        _ = try JSONObject(validating: tasks.inputSchema.bytes)
        _ = try JSONObject(validating: ideas.inputSchema.bytes)
        let bytes = [tasks, ideas].map { $0.description.utf8.count + $0.inputSchema.bytes.count }
        // ADR-0141: 1,333 bytes for the two before; 1,351 after, typed and batched.
        #expect(bytes.reduce(0, +) <= 1_360, "\(bytes)")
    }
}
