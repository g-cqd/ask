import Foundation
import Testing

@testable import AskAgentCore

/// ADR-0141's records: a call is one record, kept or lost whole; old records read unchanged; a newer ask's record makes a list read-only.
@Suite
struct ChangeRecordTests {
    private let path = NSTemporaryDirectory() + "ask-records-\(UUID().uuidString).tasks"

    @Test
    func `a call's changes are one line, and a torn one loses the call, not half of it`() throws {
        let log = try TaskLog(path: path, format: .plain, keyring: nil)
        try log.change { $0.adding(title: "before") }
        _ = try log.update { list in
            (
                try TaskPlanner.plan([.add(TaskDraft(title: "a")), .add(TaskDraft(title: "b"))], on: list, at: 1)
                    .change, ()
            )
        }
        let lines = String(decoding: try Data(contentsOf: URL(fileURLWithPath: path)), as: UTF8.self)
            .split(separator: "\n")
        #expect(lines.count == 2 && lines[1].hasPrefix(#"{"kind":"batch""#))
        try Data(lines[0].utf8 + [0x0A] + lines[1].utf8.dropLast(5)).write(to: URL(fileURLWithPath: path))
        #expect(try TaskLog(path: path, format: .plain, keyring: nil).list.tasks.map(\.title) == ["before"])
    }

    @Test
    func `records from before ADR-0141 read unchanged`() throws {
        let old =
            #"{"kind":"add","task":{"id":1,"title":"old","detail":"","state":"open","blockedBy":[],"related":[]}}"#
        let ideas = [
            #"{"add":{"_0":{"id":1,"text":"an idea","made":1793563653,"state":"new"}}}"#,
            #"{"state":{"id":1,"_1":"acknowledged"}}"#
        ]
        try Data((old + "\n").utf8).write(to: URL(fileURLWithPath: path))
        let task = try TaskLog(path: path, format: .plain, keyring: nil).list.task(1)
        #expect(task?.title == "old" && task?.tags == [] && task?.made == nil)
        try Data((ideas.joined(separator: "\n") + "\n").utf8).write(to: URL(fileURLWithPath: path))
        let idea = try ChangeLog<IdeaList>(path: path, format: .plain, keyring: nil).list.idea(1)
        #expect(idea?.state == .acknowledged && idea?.tasks == [])
    }

    @Test
    func `a record a later ask wrote leaves the list readable and refuses changes, writing nothing`() throws {
        let lines = [
            #"{"kind":"add","task":{"id":1,"title":"kept","detail":"","state":"open","blockedBy":[],"related":[]}}"#,
            #"{"kind":"archive","id":1}"#
        ]
        let bytes = Data((lines.joined(separator: "\n") + "\n").utf8)
        try bytes.write(to: URL(fileURLWithPath: path))
        let log = try TaskLog(path: path, format: .plain, keyring: nil)
        #expect(log.list.tasks.map(\.title) == ["kept"])
        #expect(throws: ListRecordError(kind: "archive")) { try log.change { $0.adding(title: "new") } }
        #expect(try Data(contentsOf: URL(fileURLWithPath: path)) == bytes)
        let idea = Data(#"{"archive":{"id":1}}"#.utf8 + [0x0A])
        try idea.write(to: URL(fileURLWithPath: path))
        #expect(throws: ListRecordError(kind: "archive")) {
            try ChangeLog<IdeaList>(path: path, format: .plain, keyring: nil).change { $0.adding("x", at: 1) }
        }
    }

    @Test
    func `a batch never holds a batch`() {
        var list = TaskList()
        #expect(throws: TaskListError.nested) { try list.apply(.batch([.batch([])])) }
        var ideas = IdeaList()
        #expect(throws: IdeaListError.nested) { try ideas.apply(.batch([.batch([])])) }
    }
}
