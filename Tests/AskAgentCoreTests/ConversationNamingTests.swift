import AemiIO
import AskAgentCore
import Foundation
import System
import Testing

/// When the conversation is named (note n60): from its first request while it has none, and again from each compaction's summary.
@Suite("A conversation is named from its first request")
struct ConversationNamingTests {
    private func recorder() throws -> (SessionRecorder, String) {
        let path = FileManager.default.temporaryDirectory.appending(path: "ask-naming-\(UUID().uuidString).jsonl").path
        return (SessionRecorder(try SessionFile.create(at: FilePath(path), durability: .none)), path)
    }

    @Test func `a new conversation is named from the request that starts it`() throws {
        let (recorder, path) = try recorder()
        defer { try? FileManager.default.removeItem(atPath: path) }
        #expect(
            ConversationNaming.source(in: recorder.tree, prompt: "fix the login redirect") == "fix the login redirect"
        )
    }

    @Test func `one resumed without a name is named from its first request, not the latest`() throws {
        let (recorder, path) = try recorder()
        defer { try? FileManager.default.removeItem(atPath: path) }
        try recorder.append(.user("fix the login redirect"))
        try recorder.append(.assistant("Done."))
        #expect(ConversationNaming.source(in: recorder.tree, prompt: "and the tests") == "fix the login redirect")
    }

    @Test func `a named one is not named again at a turn's start`() throws {
        let (recorder, path) = try recorder()
        defer { try? FileManager.default.removeItem(atPath: path) }
        try recorder.append(.user("fix the login redirect"))
        try recorder.recordThread(.renamed(ThreadRecord.conversation, to: "login redirect"))
        #expect(ConversationNaming.source(in: recorder.tree, prompt: "and the tests") == nil)
    }

    @Test func `ask's own continuation request names nothing`() throws {
        let (recorder, path) = try recorder()
        defer { try? FileManager.default.removeItem(atPath: path) }
        #expect(ConversationNaming.source(in: recorder.tree, prompt: AgentLoop.continuationPrompt) == nil)
        #expect(ConversationNaming.source(in: recorder.tree, prompt: "  ") == nil)
    }
}
