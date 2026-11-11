import AemiIO
import AskAgentCore
import Foundation
import System
import Testing

/// The conversation's own name (note n60, t235): kept in its session as a rename of the conversation, which a build that knows only
/// threads' renames reads and passes over, and which a listing shows.
@Suite("A session keeps its conversation's name")
struct ConversationNameTests {
    @Test func `the latest name is the one, a thread's rename is not it, and a listing reads it`() throws {
        let path = FileManager.default.temporaryDirectory.appending(path: "ask-convname-\(UUID().uuidString).jsonl")
            .path
        defer { try? FileManager.default.removeItem(atPath: path) }
        let recorder = SessionRecorder(try SessionFile.create(at: FilePath(path), durability: .none))
        try recorder.append(.user("fix the login redirect"))
        #expect(recorder.tree.conversationName == nil)
        #expect(SessionSummary(readingFrom: path)?.name == nil)
        try recorder.recordThread(.renamed(ThreadRecord.conversation, to: "login redirect"))
        try recorder.recordThread(.renamed("thread-1", to: "parser work"))
        try recorder.recordThread(.renamed(ThreadRecord.conversation, to: "login redirect tests"))
        #expect(recorder.tree.conversationName == "login redirect tests")
        let reread = try SessionLog.recover(Array(try Data(contentsOf: URL(fileURLWithPath: path))))
        #expect(reread.tree.conversationName == "login redirect tests")
        #expect(SessionSummary(readingFrom: path)?.name == "login redirect tests")
        #expect(SessionSummary(readingFrom: path)?.firstPrompt == "fix the login redirect")
    }

    @Test func `the conversation's id is no thread's`() {
        #expect(!ThreadRecord.conversation.hasPrefix("thread-"))
    }

    @Test func `a listing says the name, then the first request`() throws {
        let path = FileManager.default.temporaryDirectory.appending(path: "ask-convlist-\(UUID().uuidString).jsonl")
            .path
        defer { try? FileManager.default.removeItem(atPath: path) }
        let recorder = SessionRecorder(try SessionFile.create(at: FilePath(path), durability: .none))
        try recorder.append(.user("fix the login\nredirect"))
        #expect(SessionSummary(readingFrom: path)?.described(limit: 80) == "fix the login redirect")
        try recorder.recordThread(.renamed(ThreadRecord.conversation, to: "login redirect"))
        #expect(SessionSummary(readingFrom: path)?.described(limit: 80) == "login redirect · fix the login redirect")
        #expect(SessionSummary(readingFrom: path)?.described(limit: 20) == "login redirect · fi…")
    }
}
