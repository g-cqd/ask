internal import AemiSearch
internal import Foundation
internal import Testing

@testable import AskAgentCore

/// Session search (t209): plain sessions' lines become documents; an update reads only what each file gained, waits for a line's
/// end, leaves encrypted files alone, and its index and progress survive a new process.
@Suite("Session search indexes what sessions gain, and keeps it")
struct SessionSearchTests {
    private static let user =
        #"{"id":"1","parent":"0","payload":{"kind":"user","text":"why is the CacheKey wrong"},"type":"entry"}"#
    private static let reply =
        #"{"id":"2","parent":"1","payload":{"kind":"response","blocks":[{"type":"text","text":"Because the headers are unsorted."},"#
        + #"{"type":"tool_call","id":"c","name":"bash","input":{"command":"swift test --filter CacheKeyTests"}}]},"type":"entry"}"#
    private static let result =
        #"{"id":"3","parent":"2","payload":{"kind":"tool_result","content":"error: no such module 'Zlib'"},"type":"entry"}"#

    @Test func `each kind of line gives its documents, with its session, project, entry and kind`() {
        func kinds(_ line: String) -> [String] {
            SessionSearchDocuments.documents(fromLine: Array(line.utf8)[...], session: "s", project: "p", time: 1)
                .compactMap { $0.fields["kind"] }
        }
        #expect(kinds(Self.user) == ["user"])
        #expect(kinds(Self.reply) == ["reply", "call"])
        #expect(kinds(Self.result) == ["tool"])
        #expect(kinds(#"{"type":"leaf","id":null}"#).isEmpty)
        let call =
            SessionSearchDocuments.documents(fromLine: Array(Self.reply.utf8)[...], session: "s", project: "p", time: 1)[
                1
            ]
        #expect(call.text.hasPrefix("bash "), "\(call.text)")
        #expect(call.text.contains("CacheKeyTests"), "\(call.text)")
        #expect(call.fields["entry"] == "2")
    }

    private func folder() throws -> String {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ask-search-\(UUID().uuidString)")
            .path
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        return folder
    }

    @Test func `an update indexes the session's new complete lines only, and a new process carries on`() async throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(atPath: folder) }
        let file = folder + "/s1.jsonl"
        try (#"{"type":"session","version":2}"# + "\n" + Self.user + "\n" + Self.reply)
            .write(toFile: file, atomically: true, encoding: .utf8)
        let search = SessionSearch(sessionPath: file)
        #expect(await search.update() == 1, "the reply's line has no end yet")
        let handle = try #require(FileHandle(forWritingAtPath: file))
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(("\n" + Self.result + "\n").utf8))
        try handle.close()
        #expect(await search.update() == 3)
        #expect(await search.update() == 0)
        #expect(await search.search(SearchQuery("cachekey")).first?.fields["entry"] == "1")
        #expect(FileManager.default.fileExists(atPath: file + ".search"), "kept beside the session")
        let again = SessionSearch(sessionPath: file)
        #expect(await again.update() == 0, "the offset was kept")
        #expect(await again.search(SearchQuery("Zlib")).first?.fields["kind"] == "tool")
    }

    @Test func `only the session searched is read: another one's text is never found, and an encrypted one says so`()
        async throws
    {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(atPath: folder) }
        let mine = folder + "/mine.jsonl"
        let other = folder + "/other.jsonl"
        try (#"{"type":"session","version":2}"# + "\n" + Self.user + "\n")
            .write(toFile: mine, atomically: true, encoding: .utf8)
        try (#"{"type":"session","version":2}"# + "\n" + Self.result + "\n")
            .write(toFile: other, atomically: true, encoding: .utf8)
        let search = SessionSearch.of(session: mine)
        #expect(search === SessionSearch.of(session: mine), "one search per session")
        #expect(await search.search(SearchQuery("Zlib")).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: other + ".search"))
        let locked = folder + "/locked.jsonl"
        try Data([0x41, 0x53, 0x4B, 0x45, 0x00, 0x01, 0x0A]).write(to: URL(fileURLWithPath: locked))
        let encrypted = SessionSearch(sessionPath: locked)
        #expect(await encrypted.search(SearchQuery("anything")).isEmpty)
        #expect(await encrypted.unreadable)
    }
}
