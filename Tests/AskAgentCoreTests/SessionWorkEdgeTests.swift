internal import AemiJSON
internal import AemiSearch
internal import AskAI
internal import Foundation
internal import Synchronization
internal import System
internal import Testing

@testable import AskAgentCore

/// The edges of this session's additions that the mutation run found untested (2026-11-13): each assertion pins one branch.
@Suite("Edges of clearing, goals, references, search and tool prose")
struct SessionWorkEdgeTests {
    @Test func `a cleared output's line counts its lines and bytes`() {
        #expect(ContextClearing.stub(for: "a\nb\nc").contains(": 3 lines, 5 bytes."))
        #expect(ContextClearing.stub(for: "one").contains(": 1 lines, 3 bytes."))
    }

    @Test func `a met goal's notice has its evidence on a line of its own, or none`() async {
        for (reply, expected) in [("MET", "Goal met: done"), ("MET: tests pass", "Goal met: done\ntests pass")] {
            let state = GoalState()
            state.set("done")
            let seen = Mutex<[String]>([])
            let hook = GoalHook(
                state: state,
                judge: { _ in reply },
                recent: { "" },
                atBound: { _ in false },
                notice: { text in seen.withLock { $0.append(text) } }
            )
            let response = AssembledResponse(
                id: "r",
                model: "m",
                blocks: [],
                stopReason: .endTurn,
                usage: TokenUsage(),
                unrecognized: []
            )
            _ = await hook.runStop(RunStop(response: response, continued: 0))
            #expect(seen.withLock { $0 } == [expected])
        }
    }

    @Test func `references: names are ASCII letters, digits, dashes, underscores and dots; tasks need a number`() {
        #expect(ForgeReferences.repository(fromRemote: "https://github.com/Aemi_v2.x-y/r.git")?.owner == "Aemi_v2.x-y")
        #expect(ForgeReferences.repository(fromRemote: "https://github.com/ö/r") == nil)
        #expect(ForgeReferences.repository(fromRemote: "https://github.com/a+b/r") == nil)
        #expect(ForgeReferences.numbers(in: "#１２ #12") == [12], "full-width digits are no number")
        #expect(ListReferences.words("#xy #t #n2 #i") == ["n2"])
    }

    @Test func `a reply's text is a document, an empty one is not`() {
        let entry = { (text: String) in SessionEntry(id: EntryID("e"), parentID: nil, payload: .assistant(text)) }
        #expect(SessionSearchDocuments.documents(of: entry(""), time: 0).isEmpty)
        #expect(SessionSearchDocuments.documents(of: entry("hi"), time: 0).map { $0.fields["kind"] } == ["reply"])
    }

    @Test func `the kept index is the person's alone`() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "ask-edge-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let session = SessionRecorder(try SessionFile.create(at: FilePath(directory.appending(path: "s.jsonl").path)))
        _ = try session.append(.user("hello"))
        await SessionSearch(sessionPath: session.path).update(from: session)
        let mode = try FileManager.default.attributesOfItem(atPath: session.path + ".search")[.posixPermissions] as? Int
        #expect(mode == 0o600)
    }

    private func input(_ json: String) throws -> JSONObject { try JSONObject(validating: Array(json.utf8)) }

    @Test func `prose: whole numbers lose their point, records and lists in a list read inline, keys become words`()
        throws
    {
        #expect(ToolSummary.header(for: try input(#"{"n":3.0,"m":2.5,"big":1e20}"#)) == "n 3 · m 2.5 · big 1e+20")
        let details = ToolSummary.fullInput(
            for: try input(#"{"changes":[{"empty":{},"ids":"t1","sub":{"c":1},"none":[],"tags":["a","b"]}]}"#)
        )
        #expect(details == "Changes:\n  - ids t1 · sub (c 1) · tags a, b")
        #expect(ToolProse.words("timeout_seconds-max allowWrites") == "timeout seconds max allow writes")
    }
}
