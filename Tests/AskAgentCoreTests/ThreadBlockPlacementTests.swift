import AskAI
import AskAgentCore
import Testing

/// Where a thread's blocks go in its parent's conversation once a session is resumed (roadmap 0195, the audit of 2026-11-06). A merge
/// is recorded at the parent's leaf then, but its summary goes with what the parent is sent next: so it is shown at the end of the
/// turn it came in, before the next prompt, not before that turn's later replies.
@Suite("A merge is shown where its summary reaches the parent")
struct ThreadBlockPlacementTests {
    private static let reply = AssembledResponse(
        id: "r",
        model: "m",
        blocks: [.text("ok")],
        stopReason: .endTurn,
        usage: TokenUsage(),
        unrecognized: []
    )
    /// A prompt (1), a reply (2), an assistant's text (3), a reply (4); then the next prompt (5) and its reply (6).
    private static let branch: [SessionEntry] = [
        SessionEntry(id: EntryID("1"), parentID: nil, payload: .user("first")),
        SessionEntry(id: EntryID("2"), parentID: EntryID("1"), payload: .response(reply)),
        SessionEntry(id: EntryID("3"), parentID: EntryID("2"), payload: .assistant("between")),
        SessionEntry(id: EntryID("4"), parentID: EntryID("3"), payload: .response(reply)),
        SessionEntry(id: EntryID("5"), parentID: EntryID("4"), payload: .user("second")),
        SessionEntry(id: EntryID("6"), parentID: EntryID("5"), payload: .response(reply))
    ]

    @Test func `a merge during a turn is shown at the end of that turn`() {
        let merged = ThreadRecord.merged("thread-1", summary: "done", at: EntryID("2"))
        #expect(merged.shown(in: Self.branch) == EntryID("4"))
    }

    @Test func `a merge between turns stays where it was recorded`() {
        #expect(
            ThreadRecord.merged("thread-1", summary: "done", at: EntryID("4")).shown(in: Self.branch) == EntryID("4")
        )
    }

    @Test func `a merge during the last turn is shown at the end of the branch`() {
        #expect(
            ThreadRecord.merged("thread-1", summary: "done", at: EntryID("5")).shown(in: Self.branch) == EntryID("6")
        )
    }

    @Test func `a start stays where it forked, because the thread saw only that much`() {
        let started = ThreadRecord.started("thread-1", parent: nil, prompt: "x", file: "/tmp/t.jsonl", at: EntryID("2"))
        #expect(started.shown(in: Self.branch) == EntryID("2"))
    }

    @Test func `an entry not on the branch, or none, is left as it is`() {
        #expect(
            ThreadRecord.merged("thread-1", summary: "done", at: EntryID("9")).shown(in: Self.branch) == EntryID("9")
        )
        #expect(ThreadRecord.merged("thread-1", summary: "done", at: nil).shown(in: Self.branch) == nil)
    }
}
