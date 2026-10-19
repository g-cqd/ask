import AemiIO
import Foundation
import System
import Testing

@testable import AskAgentCore

/// `--continue` takes the session written last; `--resume` takes one by name. Each test owns a fresh state
/// directory, and sets modification times itself rather than waiting for the clock.
@Suite("A session to resume is found by recency or by name")
struct SessionLookupTests {
    private let directory: SessionDirectory

    init() throws {
        let state = FileManager.default.temporaryDirectory.appending(path: "ask-lookup-\(UUID().uuidString)")
        directory = SessionDirectory(project: "/p", environment: ["XDG_STATE_HOME": state.path], home: "/h")
        try FileManager.default.createDirectory(atPath: directory.path, withIntermediateDirectories: true)
    }

    @discardableResult
    private func session(_ name: String, modified seconds: TimeInterval, prompts: [String] = []) throws -> String {
        let path = directory.path + "/" + name
        var file = try SessionFile.create(at: FilePath(path), durability: .none)
        for prompt in prompts { try file.append(.user(prompt)) }
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: seconds)], ofItemAtPath: path)
        return path
    }

    @Test func `sessions are listed by last write, newest first, and damaged or temporary copies are not sessions`()
        throws
    {
        // Named oldest-first but written in another order: a resumed old session is the one to continue.
        try session("20261001T000000Z-aa.jsonl", modified: 3_000)
        try session("20261002T000000Z-bb.jsonl", modified: 1_000)
        try session("20261003T000000Z-cc.jsonl", modified: 2_000)
        for extra in ["20261001T000000Z-aa.jsonl.damaged", "20261003T000000Z-cc.jsonl.tmp", "notes.txt"] {
            try Data("x".utf8).write(to: URL(filePath: directory.path + "/" + extra))
        }
        #expect(
            directory.sessions().map(\.name) == [
                "20261001T000000Z-aa.jsonl", "20261003T000000Z-cc.jsonl", "20261002T000000Z-bb.jsonl"
            ])
    }

    @Test func `a project with no session directory has no sessions`() {
        let empty = SessionDirectory(project: "/never", environment: ["XDG_STATE_HOME": "/nonexistent"], home: "/h")
        #expect(empty.sessions().isEmpty)
    }

    @Test func `a session is found by path, by name with or without its extension, or by a unique prefix`() throws {
        let path = try session("20261001T000000Z-aa.jsonl", modified: 1)
        try session("20261002T000000Z-bb.jsonl", modified: 2)
        #expect(try directory.resolve("/elsewhere/s.jsonl") == "/elsewhere/s.jsonl")
        #expect(try directory.resolve("20261001T000000Z-aa.jsonl") == path)
        #expect(try directory.resolve("20261001T000000Z-aa") == path)
        #expect(try directory.resolve("20261001") == path)
    }

    @Test func `an unknown or ambiguous name is refused, and the ambiguity names the candidates`() throws {
        try session("20261001T000000Z-aa.jsonl", modified: 1)
        try session("20261001T120000Z-bb.jsonl", modified: 2)
        #expect(throws: SessionLookupError.notFound("2025")) { try directory.resolve("2025") }
        #expect(
            throws: SessionLookupError.ambiguous(
                "20261001", candidates: ["20261001T120000Z-bb.jsonl", "20261001T000000Z-aa.jsonl"])
        ) { try directory.resolve("20261001") }
    }

    @Test func `a summary gives the first prompt and counts the user's prompts, not ask's own`() throws {
        let path = try session(
            "s.jsonl", modified: 1, prompts: ["Fix the build.", AgentLoop.continuationPrompt, "Now the tests."])
        let summary = try #require(SessionSummary(readingFrom: path))
        #expect(summary.firstPrompt == "Fix the build.")
        #expect(summary.prompts == 2)
    }
}
