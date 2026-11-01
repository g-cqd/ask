import Testing

@testable import AskAgentCore

/// The task list of ADR-0140: ids in the order made and never reused, states, "blocked by" and "related" links, reordering, and every
/// change refused that would leave it unsound.
@Suite
struct TaskListTests {
    private func list(_ titles: [String]) throws -> TaskList {
        var list = TaskList()
        for title in titles { _ = try list.apply(list.adding(title: title)) }
        return list
    }

    @Test
    func `ids follow the order tasks are made in, and are never reused`() throws {
        var list = try list(["first", "second"])
        #expect(list.tasks.map(\.id) == [1, 2])
        try list.apply(.remove(id: 2))
        _ = try list.apply(list.adding(title: "third"))
        #expect(list.tasks.map(\.id) == [1, 3])
    }

    @Test
    func `a task is open, then in progress, then done, and can be reopened`() throws {
        var list = try list(["write it"])
        #expect(list.task(1)?.state == .open)
        try list.apply(.state(id: 1, .inProgress))
        try list.apply(.state(id: 1, .done))
        #expect(list.task(1)?.state == .done)
        try list.apply(.state(id: 1, .open))
        #expect(list.task(1)?.state == .open)
    }

    @Test
    func `a task is blocked while a task it waits on is not done, and blocking cannot go round`() throws {
        var list = try list(["design", "build", "ship"])
        try list.apply(.link(id: 2, .blockedBy, target: 1))
        try list.apply(.link(id: 3, .blockedBy, target: 2))
        #expect(list.isBlocked(2) && list.isBlocked(3) && !list.isBlocked(1))
        #expect(throws: TaskListError.cycle) { try list.apply(.link(id: 1, .blockedBy, target: 3)) }
        #expect(throws: TaskListError.cycle) { try list.apply(.link(id: 1, .blockedBy, target: 1)) }
        try list.apply(.state(id: 1, .done))
        #expect(!list.isBlocked(2) && list.isBlocked(3))
        try list.apply(.link(id: 1, .related, target: 3))
        #expect(list.task(1)?.related == [3])
        try list.apply(.unlink(id: 3, .blockedBy, target: 2))
        #expect(!list.isBlocked(3))
    }

    @Test
    func `a change naming a task that is not there, or an empty title, is refused and changes nothing`() throws {
        var list = try list(["one"])
        let before = list
        #expect(throws: TaskListError.unknownTask(9)) { try list.apply(.state(id: 9, .done)) }
        #expect(throws: TaskListError.unknownTask(9)) { try list.apply(.link(id: 1, .related, target: 9)) }
        #expect(throws: TaskListError.emptyTitle) { try list.apply(list.adding(title: "  ")) }
        #expect(throws: TaskListError.emptyTitle) { try list.apply(.edit(id: 1, title: "", detail: nil)) }
        #expect(list == before)
    }

    @Test
    func `tasks move before or after another, and a removed task leaves no link behind`() throws {
        var list = try list(["a", "b", "c"])
        try list.apply(.move(id: 3, before: 1))
        #expect(list.tasks.map(\.id) == [3, 1, 2])
        try list.apply(.move(id: 3, after: 2))
        #expect(list.tasks.map(\.id) == [1, 2, 3])
        try list.apply(.link(id: 3, .blockedBy, target: 2))
        try list.apply(.remove(id: 2))
        #expect(list.task(3)?.blockedBy == [])
    }

    @Test
    func `a title and a description are edited apart`() throws {
        var list = try list(["short"])
        try list.apply(.edit(id: 1, title: nil, detail: "the longer story"))
        try list.apply(.edit(id: 1, title: "shorter", detail: nil))
        #expect(list.task(1)?.title == "shorter" && list.task(1)?.detail == "the longer story")
    }

    @Test
    func `the slash command lists what is left, everything, or one task, and says what it could not find`() throws {
        var list = try list(["plan", "build"])
        try list.apply(.edit(id: 2, title: nil, detail: "the long part"))
        try list.apply(.state(id: 1, .done))
        #expect(list.answer(to: "") == "t2 [open] build\n(1 done, not shown)")
        #expect(list.answer(to: " all ") == "t1 [done] plan\nt2 [open] build")
        #expect(list.answer(to: "t2") == "t2 [open] build\n\nthe long part")
        #expect(list.answer(to: "2") == list.answer(to: "t2"))
        #expect(list.answer(to: "t7") == "There is no task t7.")
        #expect(list.answer(to: "what") == "Usage: /tasks, /tasks all, or /tasks t3 for one task.")
        #expect(TaskList().answer(to: "") == "No tasks yet.")
    }

    @Test
    func `a new task cannot take an id given before, nor wait on a task that is not there`() throws {
        var list = try list(["one"])
        let taken = SessionTask(id: 1, title: "again", detail: "", state: .open, blockedBy: [], related: [])
        #expect(throws: TaskListError.taken(1)) { try list.apply(.add(taken)) }
        #expect(throws: TaskListError.unknownTask(5)) { try list.apply(list.adding(title: "two", blockedBy: [5])) }
        #expect(throws: TaskListError.unknownTask(6)) { try list.apply(list.adding(title: "two", related: [6])) }
        #expect(list.tasks.count == 1)
    }
}
