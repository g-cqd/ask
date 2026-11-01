import Foundation
import Testing

@testable import AskAgentCore

/// ADR-0141's reads: views, ids in full, word search ranked by field, limits, a summary.
@Suite
struct TaskQueryTests {
    private let utc = TimeZone(identifier: "UTC")!

    private func list() throws -> TaskList {
        let plan = try TaskPlanner.plan(
            [
                .add(TaskDraft(title: "write the parser", detail: "fast lexer first", tags: ["core"])),
                .add(TaskDraft(title: "the lexer", blockedBy: [.added(1)])),
                .add(TaskDraft(title: "ship", state: .done))
            ],
            on: TaskList(),
            at: 1_793_541_900
        )
        var list = TaskList()
        try list.apply(try #require(plan.change))
        return list
    }

    @Test
    func `the open view lists what is left and counts the done ones`() throws {
        #expect(
            try TaskQuery().answer(list()) == """
                t1 [open] write the parser #core
                t2 [open, blocked by t1] the lexer
                (1 done, not shown)
                """
        )
        #expect(try TaskQuery(view: .done).answer(list()) == "t3 [done] ship")
    }

    @Test
    func `words must all appear, and a title match comes before a detail match`() throws {
        #expect(
            try TaskQuery(text: "LEXER").answer(list())
                == "t2 [open, blocked by t1] the lexer\nt1 [open] write the parser #core"
        )
        #expect(try TaskQuery(text: "core parser").answer(list()) == "t1 [open] write the parser #core")
        #expect(try TaskQuery(text: "nowhere").answer(list()) == "No task matches.")
    }

    @Test
    func `ids show their tasks in full, with when they were made and done`() throws {
        let shown = try TaskQuery(ids: [.id(3)]).answer(list(), in: utc)
        #expect(shown == "t3 [done] ship\nmade 2026-11-01 14:05 · done 2026-11-01 14:05")
        #expect(throws: ListPlanError.self) { try TaskQuery(ids: [.id(9)]).answer(list()) }
    }

    @Test
    func `a summary counts, and a limit says what it left out`() throws {
        #expect(
            try TaskQuery(view: .summary).answer(list())
                == "3 tasks: 2 open, 0 in progress, 1 done · 1 blocked · tags: core 1"
        )
        #expect(
            try TaskQuery(view: .all, limit: 2).answer(list()).hasSuffix("(1 more; raise limit, or narrow the read.)")
        )
        #expect(throws: ListPlanError.self) { try TaskQuery(limit: 0).answer(list()) }
        #expect(throws: ListPlanError.self) { try TaskQuery(limit: 201).answer(list()) }
        #expect(throws: ListPlanError.self) { try TaskQuery(text: String(repeating: "x", count: 81)).answer(list()) }
    }
}
