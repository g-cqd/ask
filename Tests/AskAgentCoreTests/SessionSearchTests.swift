internal import AemiSearch
internal import AskAI
internal import Foundation
internal import System
internal import Testing

@testable import AskAgentCore

/// Session search (t209): the current session's entries, whatever its format, indexed as they come and kept beside it; an encrypted
/// session's index sealed, never in the clear; no other session read.
@Suite("Session search indexes the session's entries, and keeps the index sealed when the session is")
struct SessionSearchTests {
    private let directory: URL
    private let keyring: SessionKeyring

    init() throws {
        directory = FileManager.default.temporaryDirectory.appending(path: "ask-search-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let made = try SessionKeys.create(password: Array("pw".utf8), derivation: SessionKeysTests.quick)
        keyring = SessionKeyring(keys: made.keys, userKey: made.userKey)
    }

    private func path(_ name: String) -> String { directory.appending(path: name).path }

    private func recorder(_ name: String, format: SessionFormat = .plain) throws -> SessionRecorder {
        let file = try SessionFile.create(
            at: FilePath(path(name)),
            format: format,
            keyring: format.encrypted ? keyring : nil
        )
        return SessionRecorder(file)
    }

    @Test func `each kind of entry gives its documents, with its entry and kind`() throws {
        let input = try JSONObject(validating: Array(#"{"command":"swift test --filter CacheKeyTests"}"#.utf8))
        let response = AssembledResponse(
            id: "m",
            model: "x",
            blocks: [.text("Because the headers are unsorted."), .toolCall(id: "c", name: "bash", input: input)],
            stopReason: .toolUse,
            usage: TokenUsage(),
            unrecognized: []
        )
        let entry = SessionEntry(id: EntryID("2"), parentID: nil, payload: .response(response))
        let documents = SessionSearchDocuments.documents(of: entry, time: 1)
        #expect(documents.map { $0.fields["kind"] } == ["reply", "call"])
        #expect(documents[1].text.hasPrefix("bash ") && documents[1].text.contains("CacheKeyTests"))
        #expect(documents[1].fields["entry"] == "2")
    }

    @Test(arguments: [SessionFormat.plain, SessionFormat(compressed: true, encrypted: false)])
    func `new entries only, any format, and a new process carries on from the kept index`(format: SessionFormat)
        async throws
    {
        let session = try recorder("s.jsonl", format: format)
        _ = try session.append(.user("why is the CacheKey wrong"))
        let search = SessionSearch(sessionPath: session.path)
        #expect(await search.update(from: session) == 1)
        _ = try session.append(.toolResult(callID: "c", content: "error: no such module 'Zlib'", isError: true))
        #expect(await search.update(from: session) == 1)
        #expect(await search.update(from: session) == 0)
        #expect(await search.search(SearchQuery("cachekey"), in: session).first?.fields["kind"] == "user")
        let again = SessionSearch(sessionPath: session.path)
        #expect(await again.update(from: session) == 0, "the count of entries was kept")
        #expect(await again.search(SearchQuery("Zlib"), in: session).first?.fields["kind"] == "tool")
    }

    @Test func `an encrypted session's index is sealed: its words are not in the file, and only the key reads it`()
        async throws
    {
        let session = try recorder("e.jsonl", format: SessionFormat(compressed: false, encrypted: true))
        _ = try session.append(.user("the secret word is xylophonist"))
        let search = SessionSearch(sessionPath: session.path)
        #expect(await search.search(SearchQuery("xylophonist"), in: session).count == 1)
        let stored = try #require(FileManager.default.contents(atPath: session.path + ".search"))
        #expect(stored.range(of: Data("xylophonist".utf8)) == nil)
        #expect(await SessionSearch(sessionPath: session.path).update(from: session) == 0, "read back under the key")
    }

    @Test func `encrypting a session drops its clear index, and the next one is sealed`() async throws {
        let session = try recorder("p.jsonl")
        _ = try session.append(.user("the secret word is xylophonist"))
        await SessionSearch(sessionPath: session.path).update(from: session)
        let clear = try #require(FileManager.default.contents(atPath: session.path + ".search"))
        #expect(clear.range(of: Data("xylophonist".utf8)) != nil)
        try session.change(to: SessionFormat(compressed: false, encrypted: true), keyring: keyring)
        #expect(!FileManager.default.fileExists(atPath: session.path + ".search"))
        _ = try session.append(.user("more"))
        await SessionSearch(sessionPath: session.path).update(from: session)
        let sealed = try #require(FileManager.default.contents(atPath: session.path + ".search"))
        #expect(sealed.range(of: Data("xylophonist".utf8)) == nil)
    }

    @Test func `only the session searched is read: another one's text is never found`() async throws {
        let mine = try recorder("mine.jsonl")
        let other = try recorder("other.jsonl")
        _ = try mine.append(.user("mine"))
        _ = try other.append(.user("Zlib is missing"))
        let search = SessionSearch.of(session: mine.path)
        #expect(search === SessionSearch.of(session: mine.path), "one search per session")
        #expect(await search.search(SearchQuery("Zlib"), in: mine).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: other.path + ".search"))
    }
}
