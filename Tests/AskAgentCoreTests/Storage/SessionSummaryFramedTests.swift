import Foundation
import System
import Testing

@testable import AskAgentCore

/// Listings of framed sessions (ADR-0138): read as JSONL ones are, and an encrypted one without its keys shown as locked.
@Suite
struct SessionSummaryFramedTests {
    @Test
    func `a framed session lists its first prompt, and an encrypted one is locked without its keys`() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "ask-summary-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let made = try SessionKeys.create(password: Array("pw".utf8), derivation: SessionKeysTests.quick)
        let keyring = SessionKeyring(keys: made.keys, userKey: made.userKey)
        for (name, format) in [
            ("c", SessionFormat(compressed: true, encrypted: false)), ("e", .init(compressed: true, encrypted: true))
        ] {
            var file = try SessionFile.create(
                at: FilePath(directory.appending(path: name).path),
                format: format,
                keyring: keyring
            )
            _ = try file.append(.user("what is in here"))
        }
        let compressed = try #require(SessionSummary(readingFrom: directory.appending(path: "c").path))
        #expect(compressed.firstPrompt == "what is in here" && !compressed.isLocked)
        let locked = try #require(SessionSummary(readingFrom: directory.appending(path: "e").path))
        #expect(locked.isLocked && locked.firstPrompt == nil)
        let opened = try #require(SessionSummary(readingFrom: directory.appending(path: "e").path, keyring: keyring))
        #expect(opened.firstPrompt == "what is in here" && opened.prompts == 1)
    }
}
