import AemiJSON
import AskAI
import Testing

@testable import AskAgentCore

/// What a done task cost (roadmap 0239): the session's entries from when it last went in progress to when it was done. Its start is
/// kept with it, and what was recorded meanwhile is counted, by each task in progress at the time.
@Suite("What a done task cost")
struct TaskSpendTests {
    private func plan(_ edits: [TaskEdit], on list: TaskList, at time: Int) throws -> TaskList {
        var next = list
        if let change = try TaskPlanner.plan(edits, on: list, at: time).change { try next.apply(change) }
        return next
    }

    @Test func `a task keeps when it went in progress; reopened it has none until it starts again`() throws {
        var list = try plan(
            [.add(TaskDraft(title: "a")), .add(TaskDraft(title: "b", state: .inProgress))],
            on: TaskList(),
            at: 100
        )
        #expect(
            list.task(1)?.started == nil && list.task(2)?.started == 100_000,
            "added in progress, started when made"
        )
        list = try plan([.state([.id(1)], .inProgress)], on: list, at: 200)
        list = try plan([.state([.id(1)], .done)], on: list, at: 260)
        #expect(
            list.task(1)?.started == 200_000 && list.task(1)?.finished == 260_000 && list.task(1)?.closed == 260,
            "kept once done"
        )
        list = try plan([.state([.id(1)], .open)], on: list, at: 300)
        #expect(list.task(1)?.started == nil && list.task(1)?.finished == nil && list.task(1)?.closed == nil)
        let task = try #require(list.task(2))
        let record = try AemiJSON.JSONEncoder().encode(task)
        #expect(try AemiJSON.JSONDecoder().decode(SessionTask.self, from: record) == task, "kept in its record")
        let old = #"{"id":3,"title":"c","detail":"","state":"done","blockedBy":[],"related":[]}"#
        #expect(
            try AemiJSON.JSONDecoder().decode(SessionTask.self, from: Array(old.utf8)).started == nil,
            "older records read"
        )
    }

    private static func entry(_ payload: SessionPayload, at milliseconds: Int) -> SessionEntry {
        SessionEntry(id: EntryID("e"), parentID: nil, payload: payload, recordedAt: milliseconds)
    }

    private static func response(output: Int) -> SessionPayload {
        .response(
            AssembledResponse(
                id: "r",
                model: "m",
                blocks: [],
                stopReason: nil,
                usage: TokenUsage(output: output),
                unrecognized: []
            )
        )
    }

    @Test func `its cost is what was recorded from its start to its end, to the millisecond`() throws {
        var tree = SessionTree()
        for (payload, time) in [
            (SessionPayload.user("before"), 99_000), (Self.response(output: 1), 99_500),
            (Self.response(output: 100), 100_199), (.user("go"), 100_200), (Self.response(output: 10), 101_000),
            (.toolResult(callID: "1", content: "", isError: false), 104_000), (Self.response(output: 20), 160_200),
            (.toolResult(callID: "2", content: "", isError: false), 160_201), (Self.response(output: 1_000), 170_000)
        ] {
            _ = try tree.append(payload, recordedAt: time)
        }
        let task = SessionTask(
            id: 1,
            title: "a",
            detail: "",
            state: .done,
            blockedBy: [],
            related: [],
            closed: 160,
            started: 100_200,
            finished: 160_200
        )
        let spend = try #require(WorkSpend.of(task, in: tree))
        #expect(spend.requests == 2 && spend.toolCalls == 1 && spend.usage.output == 30)
        #expect(
            spend.wallMilliseconds == 60_000 && spend.toolMilliseconds == 3_000 && spend.compactTokens == "↓30",
            "no input: no ↑"
        )
        #expect(
            spend.usage.output == 30,
            "the response a millisecond before and the result a millisecond after are not its own"
        )
        var notDone = task
        notDone.state = .inProgress
        #expect(WorkSpend.of(notDone, in: tree) == nil)
        var neverStarted = task
        neverStarted.started = nil
        #expect(WorkSpend.of(neverStarted, in: tree) == nil)
    }

    @Test func `/tasks says a done task's cost after its line, only when asked for done tasks or for it`() throws {
        let list = try plan(
            [.add(TaskDraft(title: "a", state: .inProgress)), .add(TaskDraft(title: "b")), .state([.added(1)], .done)],
            on: TaskList(),
            at: 100
        )
        let spent = { (task: SessionTask) in task.state == .done ? "1 request" : nil }
        #expect(list.answer(to: "all", spent: spent).hasPrefix("t1 [done] a · 1 request\nt2 [open] b"))
        #expect(list.answer(to: "t1", spent: spent).hasSuffix("\nspent 1 request"))
        #expect(!list.answer(to: "", spent: spent).contains("1 request"), "the open tasks only: no done one to say")
        #expect(!list.answer(to: "t1").contains("spent"), "nothing said without the session")
    }
}
