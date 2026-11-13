import Foundation
import Testing

@testable import AskAgentCore

/// Where a session's task list lives (ADR-0140), and how it follows a fork.
@Suite
struct TaskBoardTests {
    @Test
    func `a session's list sits beside it, and the workspace's beside every session`() {
        #expect(
            TaskBoard.path(forSessionAt: "/s/20250101T000000Z-ab.jsonl", scope: .session)
                == "/s/20250101T000000Z-ab.tasks"
        )
        #expect(TaskBoard.path(forSessionAt: "/s/20250101T000000Z-ab.jsonl", scope: .workspace) == "/s/tasks.ask")
    }

    @Test
    func `a fork takes a copy of its session's own list, and shares the workspace's`() throws {
        let directory = NSTemporaryDirectory() + "ask-board-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let board = TaskBoard()
        #expect(try board.current() == nil && !board.isAttached)
        try board.attach(sessionPath: directory + "/a.jsonl", format: .plain, keyring: nil, scope: .session)
        try board.change { $0.adding(title: "carried over") }
        try TaskBoard.copyForFork(from: directory + "/a.jsonl", to: directory + "/b.jsonl", scope: .session)
        try TaskBoard.copyForFork(from: directory + "/a.jsonl", to: directory + "/c.jsonl", scope: .workspace)
        // A copy that cannot be made is an error the fork tells the person of, not an empty list (roadmap 0230).
        #expect(throws: CocoaError.self) {
            try TaskBoard.copyForFork(from: directory + "/a.jsonl", to: directory + "/b.jsonl", scope: .session)
        }
        try board.attach(sessionPath: directory + "/b.jsonl", format: .plain, keyring: nil, scope: .session)
        try board.change { $0.adding(title: "only in the fork") }
        #expect(try board.current()?.tasks.map(\.title) == ["carried over", "only in the fork"])
        try board.attach(sessionPath: directory + "/a.jsonl", format: .plain, keyring: nil, scope: .session)
        #expect(try board.current()?.tasks.map(\.title) == ["carried over"])
        #expect(!FileManager.default.fileExists(atPath: directory + "/c.tasks"))
        board.detach()
        #expect(try board.change { $0.adding(title: "nowhere") } == nil)
    }
}
