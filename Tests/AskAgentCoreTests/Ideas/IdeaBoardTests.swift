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
}
