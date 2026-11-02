import Foundation
import Testing

@testable import AskAgentCore

/// Ideas kept on the task list's store (ADR-0140): beside the session or the workspace's sessions, in the session's format.
@Suite
struct IdeaBoardTests {
    @Test
    func `ideas sit beside their session, apart from its tasks, and the workspace's in ideas.ask`() {
        #expect(IdeaBoard.path(forSessionAt: "/s/a.jsonl", scope: .session) == "/s/a.ideas")
        #expect(IdeaBoard.path(forSessionAt: "/s/a.jsonl", scope: .workspace) == "/s/ideas.ask")
    }

    @Test
    func `an encrypted session's ideas read back verbatim, and are not in the clear`() throws {
        let directory = NSTemporaryDirectory() + "ask-ideas-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let made = try SessionKeys.create(password: Array("pw".utf8), derivation: SessionKeysTests.quick)
        let keyring = SessionKeyring(keys: made.keys, userKey: made.userKey)
        let format = SessionFormat(compressed: true, encrypted: true)
        let board = IdeaBoard()
        try board.attach(sessionPath: directory + "/a.jsonl", format: format, keyring: keyring, scope: .session)
        try board.change { $0.adding("a quiet\nthought ", at: 1) }
        try board.change { _ in .state(id: 1, .acknowledged) }
        let reopened = IdeaBoard()
        try reopened.attach(sessionPath: directory + "/a.jsonl", format: .plain, keyring: keyring, scope: .session)
        #expect(
            try reopened.current()?.idea(1)
                == Idea(id: 1, text: "a quiet\nthought ", made: 1, edited: nil, state: .acknowledged)
        )
        let bytes = try Data(contentsOf: URL(fileURLWithPath: directory + "/a.ideas"))
        #expect(!String(decoding: bytes, as: UTF8.self).contains("quiet"))
    }

    /// An idea typed before the session starts (the owner's choice, 2026-11-02): kept, then saved, in order and with the time it was
    /// typed, once the session's list is attached.
    @Test
    func `changes held before a list is attached are made once it is, in order, and only once`() throws {
        let directory = NSTemporaryDirectory() + "ask-ideas-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let board = IdeaBoard()
        #expect(try board.applyHeld().isEmpty, "nothing held, nothing to do")
        #expect(board.hold { $0.adding("first", at: 10) } == 1)
        #expect(board.hold { $0.adding("second", at: 20) } == 2)
        #expect(try board.current() == nil, "held, not made")
        try board.attach(sessionPath: directory + "/a.jsonl", format: .plain, keyring: nil, scope: .session)
        let made = try board.applyHeld()
        #expect(made.count == 2)
        #expect(made.last?.ideas.map(\.text) == ["first", "second"])
        #expect(try board.current()?.idea(1)?.made == 10, "the time it was typed")
        #expect(try board.applyHeld().isEmpty, "made once")
        #expect(try board.current()?.ideas.count == 2)
    }

    @Test
    func `held changes wait while no list is attached`() throws {
        let board = IdeaBoard()
        board.hold { $0.adding("x", at: 1) }
        #expect(try board.applyHeld().isEmpty, "nothing attached: still held")
        #expect(board.heldCount == 1)
    }
}
