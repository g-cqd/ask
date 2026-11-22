internal import Darwin
internal import Foundation
internal import Testing

@testable import AskAgentCore

/// What the person allowed for the session survives `/reload` (roadmap 0159): written to a private file by the old process and read,
/// then removed, by the new one.
@Suite("The session's grants are carried across a reload")
struct SessionGrantsTests {
    private func grants() -> SessionGrants {
        var calls = CallGrants()
        calls.grant(.command(CommandWords("git status")))
        calls.grantPrograms(CommandWords("swift build"))
        calls.grant(.file("/p/notes.md"))
        calls.grant(.tool("job"))
        return SessionGrants(
            calls: calls,
            sandbox: [SandboxRequest(network: .any), SandboxRequest(write: ["/p/out"], read: ["/data"])],
            destructive: ["docs/delete"]
        )
    }

    @Test func `written and read back, every grant still covers what it did`() throws {
        let path = NSTemporaryDirectory() + "ask-grants-" + UUID().uuidString + ".json"
        try grants().write(to: path)
        let attributes = try FileManager.default.attributesOfItem(atPath: path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600, "only the person can read it")
        let read = try #require(SessionGrants.take(from: path))
        #expect(!FileManager.default.fileExists(atPath: path), "read once, then gone")
        #expect(read == grants())
        #expect(read.calls.covers(.command(CommandWords("git status -s"))))
        #expect(read.calls.covers(.command(CommandWords("swift test"))), "the program was allowed")
        #expect(read.calls.covers(.file("/p/notes.md")) && read.calls.covers(.tool("job")))
        #expect(!read.calls.covers(.command(CommandWords("rm -rf x"))))
    }

    @Test func `a missing or damaged file gives nothing, and is removed`() throws {
        #expect(SessionGrants.take(from: "/nonexistent/ask-grants.json") == nil)
        let path = NSTemporaryDirectory() + "ask-grants-" + UUID().uuidString + ".json"
        try Data("not json".utf8).write(to: URL(fileURLWithPath: path))
        #expect(SessionGrants.take(from: path) == nil && !FileManager.default.fileExists(atPath: path))
    }

    /// Security audit 2026-11-22, HIGH-10: grants let calls run unasked, so only a file the person alone could have written is read.
    @Test func `a file others may write, a link, or a name already taken is neither read nor written through`() throws {
        let base = NSTemporaryDirectory() + "ask-grants-" + UUID().uuidString
        let open = base + "-open.json"
        try grants().write(to: open)
        #expect(chmod(open, 0o644) == 0)
        #expect(
            SessionGrants.take(from: open) == nil && !FileManager.default.fileExists(atPath: open),
            "readable by others: refused"
        )
        let real = base + "-real.json"
        let link = base + "-link.json"
        try grants().write(to: real)
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: real)
        #expect(SessionGrants.take(from: link) == nil, "a link is not followed")
        #expect(FileManager.default.fileExists(atPath: real), "and what it pointed at is left alone")
        #expect(throws: (any Error).self, "a name already taken is not written over") { try grants().write(to: real) }
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: base + "-elsewhere.json")
        #expect(throws: (any Error).self, "nor written through a link") { try grants().write(to: link) }
        #expect(!FileManager.default.fileExists(atPath: base + "-elsewhere.json"))
        for path in [real, link] { try? FileManager.default.removeItem(atPath: path) }
    }
}
