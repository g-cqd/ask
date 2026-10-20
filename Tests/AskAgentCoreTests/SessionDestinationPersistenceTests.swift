internal import Foundation
internal import System
internal import Testing

@testable import AskAgentCore

struct SessionDestinationPersistenceTests {
    private let selected = SessionDestination(
        connectionID: "connection-one", authorizationID: "revision-one", name: "work-label", model: "server-model")

    @Test func `routing round trips but never becomes model input or a replayed prompt`() throws {
        var tree = SessionTree()
        try tree.append(.destination(selected))
        try tree.append(.user("hello"))
        let restored = try SessionLog.decode(SessionLog.snapshot(tree))
        #expect(restored.destination == selected)
        #expect(restored.entries == tree.entries)
        let context = RequestContext(restored.context())
        #expect(context.messages.count == 1)
        #expect(!String(describing: context.messages).contains("work-label"))
        #expect(!String(describing: context.messages).contains("revision-one"))
        #expect(SessionReplay.steps(restored.activeBranch()) == [.prompt("hello")])
        #expect(SessionSummary(restored).prompts == 1)
    }

    @Test func `the active branch determines the destination even after compaction`() throws {
        var tree = SessionTree()
        let root = try tree.append(.destination(selected))
        let kept = try tree.append(.user("keep"))
        try tree.append(.compaction(summary: "summary", firstKept: kept))
        #expect(tree.destination == selected)
        let other = SessionDestination(
            connectionID: "connection-two", authorizationID: "revision-two", name: "other", model: "another-model")
        try tree.continuing(from: root, with: .destination(other))
        #expect(tree.destination == other)
        try tree.moveLeaf(to: kept)
        #expect(tree.destination == selected)
    }

    @Test func `an unapproved destination change writes nothing and an explicit one is persisted`() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "ask-route-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let path = root.appending(path: "session.jsonl")
        let recorder = SessionRecorder(try SessionFile.create(at: FilePath(path.path)))
        try recorder.select(selected, explicitlySelected: false)
        try recorder.append(.user("hello"))
        let before = try Data(contentsOf: path)
        let other = SessionDestination(
            connectionID: "connection-two", authorizationID: "revision-two", name: "other", model: "another-model")
        #expect(throws: SessionDestinationError.changed) { try recorder.select(other, explicitlySelected: false) }
        #expect(try Data(contentsOf: path) == before)
        try recorder.select(other, explicitlySelected: true)
        #expect(recorder.destination == other)
        #expect(try SessionLog.decode(Array(Data(contentsOf: path))).destination == other)
    }
}
