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

    private func root() throws -> String {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ask-search-\(UUID().uuidString)").path
        try FileManager.default.createDirectory(atPath: root + "/sessions/proj", withIntermediateDirectories: true)
        return root
    }

    @Test func `an update indexes new complete lines only, skips encrypted files, and a new process carries on`()
        async throws
    {
        let root = try root()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let file = root + "/sessions/proj/s1.jsonl"
        try (#"{"type":"session","version":2}"# + "\n" + Self.user + "\n" + Self.reply)
            .write(toFile: file, atomically: true, encoding: .utf8)
        try Data([0x41, 0x53, 0x4B, 0x45, 0x00, 0x01])
            .write(to: URL(fileURLWithPath: root + "/sessions/proj/locked.jsonl"))
        let search = SessionSearch(root: root)
        #expect(await search.update() == 1, "the reply's line has no end yet")
        let handle = try #require(FileHandle(forWritingAtPath: file))
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(("\n" + Self.result + "\n").utf8))
        try handle.close()
        #expect(await search.update() == 3)
        #expect(await search.update() == 0)
        let hits = await search.search(SearchQuery("cachekey"))
        #expect(hits.first?.fields["session"] == "s1")
        let again = SessionSearch(root: root)
        #expect(await again.update() == 0, "the progress was kept")
        #expect(await again.search(SearchQuery("Zlib")).first?.fields["kind"] == "tool")
    }
}
