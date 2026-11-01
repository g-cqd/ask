import AskAI
import AskAgentCore
import Foundation
import Testing

@testable import AskTools

/// The `tasks` tool (ADR-0140): the model's way to the session's list, read only when called.
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
        await TasksTool(board: board).run(try JSONObject(validating: Array(json.utf8)), in: context)
    }

    @Test
    func `tasks are added, started, done, and the list shows what is left`() async throws {
        _ = try await call(#"{"action":"add","title":"write the parser","detail":"a recursive descent one"}"#)
        _ = try await call(#"{"action":"add","title":"ship it","blocked_by":["t1"]}"#)
        #expect(
            try await call(#"{"action":"list"}"#).content
                == "t1 [open] write the parser\nt2 [open, blocked by t1] ship it"
        )
        _ = try await call(#"{"action":"start","id":"t1"}"#)
        _ = try await call(#"{"action":"done","id":1}"#)
        #expect(try await call(#"{"action":"list"}"#).content == "t2 [open] ship it\n(1 done, not shown)")
        #expect(try await call(#"{"action":"list","all":true}"#).content.hasPrefix("t1 [done] write the parser"))
        #expect(try await call(#"{"action":"show","id":"t1"}"#).content.contains("a recursive descent one"))
    }

    @Test
    func `links, moves and edits change the list, and a wrong id is told plainly`() async throws {
        for title in ["a", "b", "c"] { _ = try await call(#"{"action":"add","title":"\#(title)"}"#) }
        _ = try await call(#"{"action":"move","id":"t3","before":"t1"}"#)
        _ = try await call(#"{"action":"link","id":"t3","related":"t2"}"#)
        _ = try await call(#"{"action":"edit","id":"t2","title":"b, better"}"#)
        #expect(
            try await call(#"{"action":"list"}"#).content
                == "t3 [open] c · related t2\nt1 [open] a\nt2 [open] b, better"
        )
        let wrong = try await call(#"{"action":"done","id":"t9"}"#)
        #expect(wrong.isError && wrong.content.contains("t9"))
        let cycle = try await call(#"{"action":"link","id":"t1","blocked_by":"t1"}"#)
        #expect(cycle.isError && cycle.content.contains("wait"))
    }

    @Test
    func `before a session there is no list, and the tool says so`() async throws {
        let output = await TasksTool(board: TaskBoard())
            .run(try JSONObject(validating: Array(#"{"action":"list"}"#.utf8)), in: context)
        #expect(output.isError)
    }
}
