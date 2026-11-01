import Foundation
import Testing

@testable import AskAgentCore

/// A task list's file (ADR-0140): its changes in the session's format, replayed when read, repaired as a session is, and safe for two
/// processes sharing a workspace's list.
@Suite
struct TaskLogTests {
    static let formats = [
        SessionFormat.plain, SessionFormat(compressed: true, encrypted: false),
        SessionFormat(compressed: true, encrypted: true)
    ]
    private let directory: String
    private let keyring: SessionKeyring

    init() throws {
        directory = NSTemporaryDirectory() + "ask-tasks-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let made = try SessionKeys.create(password: Array("pw".utf8), derivation: SessionKeysTests.quick)
        keyring = SessionKeyring(keys: made.keys, userKey: made.userKey)
    }

    private var path: String { directory + "/s.tasks" }

    @Test(arguments: formats)
    func `changes survive reopening, and ids are never reused`(format: SessionFormat) throws {
        do {
            let log = try TaskLog(path: path, format: format, keyring: keyring)
            try log.change { $0.adding(title: "one") }
            try log.change { $0.adding(title: "two") }
            try log.change { _ in .remove(id: 2) }
            try log.change { _ in .state(id: 1, .inProgress) }
        }
        let reopened = try TaskLog(path: path, format: format, keyring: keyring)
        #expect(reopened.list.tasks.map(\.id) == [1] && reopened.list.task(1)?.state == .inProgress)
        try reopened.change { $0.adding(title: "three") }
        #expect(reopened.list.tasks.map(\.id) == [1, 3])
        if format.encrypted {
            #expect(
                !String(decoding: try Data(contentsOf: URL(fileURLWithPath: path)), as: UTF8.self).contains("three")
            )
            #expect(throws: SessionFileError.locked) { _ = try TaskLog(path: path, format: format, keyring: nil) }
        }
    }

    @Test(arguments: formats)
    func `a torn last record is dropped, and the next change writes a clean file`(format: SessionFormat) throws {
        do {
            let log = try TaskLog(path: path, format: format, keyring: keyring)
            try log.change { $0.adding(title: "kept") }
            try log.change { $0.adding(title: "torn") }
        }
        let whole = try Data(contentsOf: URL(fileURLWithPath: path))
        try whole.dropLast(3).write(to: URL(fileURLWithPath: path))
        let log = try TaskLog(path: path, format: format, keyring: keyring)
        #expect(log.list.tasks.map(\.title) == ["kept"])
        try log.change { $0.adding(title: "after") }
        let reopened = try TaskLog(path: path, format: format, keyring: keyring)
        #expect(reopened.list.tasks.map(\.title) == ["kept", "after"])
    }

    @Test(arguments: formats)
    func `two processes sharing a list each see the other's changes before making theirs`(format: SessionFormat) throws
    {
        let first = try TaskLog(path: path, format: format, keyring: keyring)
        let second = try TaskLog(path: path, format: format, keyring: keyring)
        try first.change { $0.adding(title: "from the first") }
        try second.change { $0.adding(title: "from the second") }
        try first.change { _ in .link(id: 1, .related, target: 2) }
        let reopened = try TaskLog(path: path, format: format, keyring: keyring)
        #expect(reopened.list.tasks.map(\.title) == ["from the first", "from the second"])
        #expect(reopened.list.task(1)?.related == [2])
        #expect(try second.current().task(1)?.related == [2])
    }

    @Test
    func `a refused change writes nothing`() throws {
        let log = try TaskLog(path: path, format: .plain, keyring: nil)
        try log.change { $0.adding(title: "one") }
        let before = try Data(contentsOf: URL(fileURLWithPath: path))
        #expect(throws: TaskListError.unknownTask(7)) { try log.change { _ in .state(id: 7, .done) } }
        #expect(try Data(contentsOf: URL(fileURLWithPath: path)) == before)
    }

    @Test
    func `a list changes format with its session, and reads back in the new one`() throws {
        let log = try TaskLog(path: path, format: .plain, keyring: keyring)
        try log.change { $0.adding(title: "secret plan") }
        try log.convert(to: SessionFormat(compressed: true, encrypted: true))
        #expect(!String(decoding: try Data(contentsOf: URL(fileURLWithPath: path)), as: UTF8.self).contains("secret"))
        try log.change { $0.adding(title: "more") }
        let reopened = try TaskLog(path: path, format: .plain, keyring: keyring)
        #expect(reopened.list.tasks.map(\.title) == ["secret plan", "more"])
        try reopened.convert(to: .plain)
        #expect(
            String(decoding: try Data(contentsOf: URL(fileURLWithPath: path)), as: UTF8.self).contains("secret plan")
        )
    }

    @Test(arguments: formats)
    func `changes made at once through two logs of one file are all kept, each task with its own id`(
        format: SessionFormat
    ) async throws {
        let logs = [
            try TaskLog(path: path, format: format, keyring: keyring),
            try TaskLog(path: path, format: format, keyring: keyring)
        ]
        try await withThrowingTaskGroup(of: Void.self) { group in
            for (index, log) in logs.enumerated() {
                group.addTask { for step in 0 ..< 20 { try log.change { $0.adding(title: "\(index)-\(step)") } } }
            }
            try await group.waitForAll()
        }
        let reopened = try TaskLog(path: path, format: format, keyring: keyring)
        #expect(reopened.list.tasks.map(\.id) == Array(1 ... 40))
    }

    @Test
    func `a file larger than any list grows to is refused unread`() throws {
        try Data(count: TaskLog.largest + 1).write(to: URL(fileURLWithPath: path))
        #expect(throws: SessionFileError.self) { _ = try TaskLog(path: path, format: .plain, keyring: nil) }
    }
}
