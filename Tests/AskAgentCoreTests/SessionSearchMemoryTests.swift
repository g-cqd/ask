import AemiSearch
import Foundation
import System
import Testing

@testable import AskAgentCore

/// The index of a long session is as large as the session (70 MB for one of 81 MB, 62 MB once read; diary 2026-11-15-12) and is
/// used a few times in its life. It is in its file, so it is not also kept in memory between two uses.
@Suite("A search index that is in its file is not kept in memory")
struct SessionSearchMemoryTests {
    private let directory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory.appending(path: "ask-search-memory-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func recorder() throws -> SessionRecorder {
        SessionRecorder(try SessionFile.create(at: FilePath(directory.appending(path: "s.jsonl").path), format: .plain))
    }

    @Test func `after a search or an update the index is let go, and the next one reads it again and carries on`()
        async throws
    {
        let session = try recorder()
        _ = try session.append(.user("why is the CacheKey wrong"))
        let search = SessionSearch(sessionPath: session.path)
        #expect(await search.search(SearchQuery("cachekey"), in: session).count == 1)
        #expect(await !search.holdsIndex, "written, so let go")
        _ = try session.append(.toolResult(callID: "c", content: "error: no such module 'Zlib'", isError: true))
        #expect(await search.update(from: session) == 1, "only the new entry is indexed")
        #expect(await !search.holdsIndex)
        #expect(await search.search(SearchQuery("cachekey"), in: session).first?.fields["kind"] == "user")
        #expect(await search.search(SearchQuery("Zlib"), in: session).first?.fields["kind"] == "tool")
        #expect(await search.update(from: session) == 0)
        #expect(await !search.holdsIndex)
    }

    @Test func `an index whose file was lost meanwhile is built again from the session`() async throws {
        let session = try recorder()
        _ = try session.append(.user("why is the CacheKey wrong"))
        let search = SessionSearch(sessionPath: session.path)
        await search.update(from: session)
        try FileManager.default.removeItem(atPath: session.path + ".search")
        #expect(await search.search(SearchQuery("cachekey"), in: session).count == 1)
        #expect(FileManager.default.fileExists(atPath: session.path + ".search"), "and written again")
    }

    @Test func `an index that could not be written stays in memory, and is not built again for each search`()
        async throws
    {
        let session = try recorder()
        _ = try session.append(.user("why is the CacheKey wrong"))
        // Its file would be in a folder that is not there: nothing is written.
        let search = SessionSearch(sessionPath: directory.appending(path: "missing/s.jsonl").path)
        #expect(await search.search(SearchQuery("cachekey"), in: session).count == 1)
        #expect(await search.holdsIndex, "the only copy")
        #expect(await search.update(from: session) == 0, "nothing is indexed twice")
        #expect(await search.search(SearchQuery("cachekey"), in: session).count == 1)
    }
}
