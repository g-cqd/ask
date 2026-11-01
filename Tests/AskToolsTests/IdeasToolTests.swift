import AskAI
import AskAgentCore
import Foundation
import Testing

@testable import AskTools

/// The `ideas` tool (roadmap 0180): the model reads the person's ideas and marks them; it never writes or rewrites one.
@Suite
struct IdeasToolTests {
    private let board = IdeaBoard()
    private let context = ToolContext(workingDirectory: "/tmp")

    init() throws {
        let directory = NSTemporaryDirectory() + "ask-ideas-tool-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        try board.attach(sessionPath: directory + "/s.jsonl", format: .plain, keyring: nil, scope: .session)
        try board.change { $0.adding("fold the sidebar\nwhen narrow", at: 0) }
        try board.change { $0.adding("a second thought", at: 60) }
    }

    private func call(_ json: String) async throws -> ToolOutput {
        await IdeasTool(board: board).run(try JSONObject(validating: Array(json.utf8)), in: context)
    }

    @Test
    func `the model lists the ideas, reads one whole, and marks them`() async throws {
        let listed = try await call(#"{"action":"list"}"#).content
        #expect(listed.hasPrefix("2 new.\ni1 [new] ") && listed.contains("fold the sidebar when narrow"))
        #expect(try await call(#"{"action":"show","id":"i1"}"#).content.hasSuffix("fold the sidebar\nwhen narrow"))
        _ = try await call(#"{"action":"acknowledge","id":"i1"}"#)
        _ = try await call(#"{"action":"fulfil","id":2}"#)
        #expect(try board.current()?.idea(1)?.state == .acknowledged && board.current()?.idea(2)?.state == .fulfilled)
        _ = try await call(#"{"action":"dismiss","id":"i1"}"#)
        #expect(
            try await call(#"{"action":"list"}"#).content
                .hasPrefix("No new ideas.\nEvery idea is fulfilled or dismissed.")
        )
        _ = try await call(#"{"action":"reopen","id":"i1"}"#)
        #expect(try board.current()?.idea(1)?.state == .acknowledged)
    }

    @Test
    func `it cannot add or rewrite an idea, and a wrong id is told plainly`() async throws {
        let add = try await call(#"{"action":"add","id":"i1"}"#)
        #expect(add.isError && add.content.contains("acknowledge"))
        let wrong = try await call(#"{"action":"fulfil","id":"i9"}"#)
        #expect(wrong.isError && wrong.content.contains("i9"))
        #expect(try board.current()?.ideas.map(\.text) == ["fold the sidebar\nwhen narrow", "a second thought"])
    }

    @Test
    func `before a session there are no ideas, and the tool says so`() async throws {
        let output = await IdeasTool(board: IdeaBoard())
            .run(try JSONObject(validating: Array(#"{"action":"list"}"#.utf8)), in: context)
        #expect(output.isError)
    }
}
