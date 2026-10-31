internal import Foundation
internal import Testing

@testable import AskAI

/// Roadmap 0092: which account a model shared by several accounts was last chosen with, so `/model` asks once.
struct ModelAccountMemoryTests {
    private let url = FileManager.default.temporaryDirectory.appending(path: "ask-memory-\(UUID().uuidString)")
        .appending(path: "model-accounts.json")

    @Test func `nothing is remembered before a choice, and no file is made by reading`() {
        let memory = ModelAccountMemory(url: url)
        #expect(memory.account(for: "gpt-6", kind: .codex) == nil)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func `a choice is remembered per model and per provider, and a later one replaces it`() throws {
        let memory = ModelAccountMemory(url: url)
        try memory.remember("codex-2", for: "gpt-6", kind: .codex)
        try memory.remember("work", for: "m", kind: .anthropic)
        #expect(memory.account(for: "gpt-6", kind: .codex) == "codex-2")
        #expect(memory.account(for: "gpt-6", kind: .anthropic) == nil)
        try memory.remember("codex", for: "gpt-6", kind: .codex)
        #expect(ModelAccountMemory(url: url).account(for: "gpt-6", kind: .codex) == "codex")
        #expect(memory.account(for: "m", kind: .anthropic) == "work")
    }

    @Test func `a damaged file is read as nothing remembered, and the next choice rewrites it`() throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: url)
        let memory = ModelAccountMemory(url: url)
        #expect(memory.account(for: "gpt-6", kind: .codex) == nil)
        try memory.remember("codex-2", for: "gpt-6", kind: .codex)
        #expect(memory.account(for: "gpt-6", kind: .codex) == "codex-2")
    }
}
