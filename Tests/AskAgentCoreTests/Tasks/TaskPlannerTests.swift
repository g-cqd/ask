import Testing

@testable import AskAgentCore

/// ADR-0141's planner: a call's changes in order on a copy, all or none, what is already so changing nothing, the limits enforced.
@Suite
struct TaskPlannerTests {
    private func planned(_ edits: [TaskEdit], on list: TaskList = TaskList()) throws(ListPlanError) -> (
        TaskList, TaskReport
    ) {
        let plan = try TaskPlanner.plan(edits, on: list, at: 100)
        var next = list
        if let change = plan.change { try? next.apply(change) }
        return (next, plan.report)
    }

    private func refusal(_ edits: [TaskEdit], on list: TaskList = TaskList()) -> String? {
        do {
            _ = try TaskPlanner.plan(edits, on: list, at: 100)
            return nil
        } catch {
            return error.words
        }
    }

    @Test
    func `many changes are one batch, and @n names this call's adds`() throws {
        let (list, report) = try planned([
            .add(TaskDraft(title: "a")), .add(TaskDraft(title: "b", blockedBy: [.added(1)])),
            .state([.added(2)], .inProgress)
        ])
        #expect(list.task(2)?.blockedBy == [1] && list.task(2)?.state == .inProgress && list.task(1)?.made == 100)
        #expect(report.summary == "added t1–t2 (2) · in progress t2")
        #expect(refusal([.state([.added(1)], .done)])?.contains("@1 names an add this call has not made yet") == true)
    }

    @Test
    func `titles are unique, one line, and limited; an add of an existing title and detail is that task`() throws {
        let (list, _) = try planned([.add(TaskDraft(title: "a", detail: "x")), .state([.id(1)], .done)])
        let (again, report) = try planned(
            [.add(TaskDraft(title: "a", detail: "x")), .state([.added(1)], .done)],
            on: list
        )
        #expect(again == list && report.summary == "already so: t1")
        #expect(
            refusal([.add(TaskDraft(title: "a", detail: "y"))], on: list)?.contains("t1 already has this title") == true
        )
        #expect(refusal([.add(TaskDraft(title: "two\nlines"))])?.contains("one line") == true)
        #expect(refusal([.add(TaskDraft(title: String(repeating: "x", count: 121)))])?.contains("at most 120") == true)
        #expect(
            refusal([.add(TaskDraft(title: "b")), .edit(.id(2), title: "a", detail: nil, tags: nil)], on: list) != nil
        )
    }

    @Test
    func `a refusal names its change, and the changes before it are not made`() {
        let words = refusal([.add(TaskDraft(title: "a")), .add(TaskDraft(title: "b")), .remove([.id(7)])])
        #expect(words == "Refused, nothing changed: change 3 (remove): there is no task t7.")
    }

    @Test
    func `removing a removed task is no change, and an id never given is refused`() throws {
        let (list, _) = try planned([.add(TaskDraft(title: "a")), .add(TaskDraft(title: "b"))])
        let (removed, _) = try planned([.remove([.id(2)])], on: list)
        let (_, report) = try planned([.remove([.id(2)])], on: removed)
        #expect(report.summary == "already so: t2")
        #expect(refusal([.remove([.id(3)])], on: removed)?.contains("there is no task t3") == true)
    }

    @Test
    func `links refuse a cycle and a self-link; moves go before a task or to the end, once`() throws {
        let (list, _) = try planned([
            .add(TaskDraft(title: "a")), .add(TaskDraft(title: "b", blockedBy: [.id(1)])), .add(TaskDraft(title: "c"))
        ])
        #expect(
            refusal([.link([.id(1)], blockedBy: [.id(2)], related: [])], on: list)?.contains("wait on itself") == true
        )
        #expect(refusal([.link([.id(1)], blockedBy: [], related: [.id(1)])], on: list)?.contains("itself") == true)
        let (moved, report) = try planned([.move(.id(1), .end), .move(.id(3), .before(.id(2)))], on: list)
        #expect(moved.tasks.map(\.id) == [3, 2, 1] && report.summary == "moved t1 t3 (2)")
        #expect(try planned([.move(.id(1), .end)], on: moved).1.summary == "already so: t1")
        let (linked, again) = try planned([.link([.id(3)], blockedBy: [], related: [.id(1)])], on: moved)
        #expect(linked.task(3)?.related == [1] && again.summary == "linked t3")
        #expect(
            try planned([.link([.id(3)], blockedBy: [], related: [.id(1)])], on: linked).1.summary == "already so: t3"
        )
    }

    @Test
    func `the limits of a call and a list hold`() throws {
        #expect(refusal([])?.contains("1 to 100 changes") == true)
        #expect(refusal(Array(repeating: .state([.id(1)], .done), count: 101))?.contains("1 to 100 changes") == true)
        let (list, _) = try planned([.add(TaskDraft(title: "a"))])
        #expect(
            refusal([.state([.range(1 ... 1)], .done), .state([.range(1 ... 1000)], .done)], on: list)?
                .contains("at most 1000 ids") == true
        )
        let tags = (1 ... 9).map { "t\($0)" }
        #expect(refusal([.add(TaskDraft(title: "x", tags: tags))])?.contains("at most 8 tags") == true)
        #expect(refusal([.add(TaskDraft(title: "x", tags: ["Bad Tag"]))])?.contains("is not [a-z0-9-]") == true)
        #expect(
            refusal([.add(TaskDraft(title: "x", detail: String(repeating: "d", count: 4001)))])?
                .contains("at most 4000") == true
        )
    }

    @Test
    func `a task made done keeps when, and loses it when reopened`() throws {
        let (list, _) = try planned([.add(TaskDraft(title: "a", state: .done))])
        #expect(list.task(1)?.closed == 100)
        let (open, _) = try planned([.state([.id(1)], .open)], on: list)
        #expect(open.task(1)?.closed == nil)
    }

    @Test
    func `one-task operations refuse a range, a task cannot move next to itself, and a move already made is no change`()
        throws
    {
        let (list, _) = try planned([
            .add(TaskDraft(title: "a")), .add(TaskDraft(title: "b")), .add(TaskDraft(title: "c"))
        ])
        #expect(
            refusal([.edit(.range(1 ... 2), title: nil, detail: "x", tags: nil)], on: list)?
                .contains("one task, not a range") == true
        )
        #expect(refusal([.move(.id(1), .before(.id(1)))], on: list)?.contains("next to itself") == true)
        #expect(try planned([.move(.id(1), .before(.id(2)))], on: list).1.summary == "already so: t1")
    }

    @Test
    func `a list holds at most 2,000 tasks, and done through state keeps when`() throws {
        var full = TaskList()
        for _ in 1 ... ListLimits.entries { try full.apply(full.adding(title: "t\(full.nextID)")) }
        #expect(refusal([.add(TaskDraft(title: "one more"))], on: full)?.contains("at most 2000 tasks") == true)
        let (list, _) = try planned([.add(TaskDraft(title: "a")), .state([.added(1)], .done)])
        #expect(list.task(1)?.closed == 100)
    }
}
