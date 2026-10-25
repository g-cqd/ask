import AemiIO
import Foundation
import System
import Testing

@testable import AskAgentCore

/// Going back to an earlier point is recorded in the session itself, so a resumed session is where the person left it (ADR-0093).
@Suite("A checkout through the recorder is persisted and nothing is removed")
struct SessionRecorderCheckoutTests {
    private let path: FilePath

    init() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "ask-checkout-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        path = FilePath(directory.appending(path: "s.jsonl").path)
    }

    @Test func `the leaf moves, every entry stays, and a reopened session is where the checkout left it`() throws {
        let first: EntryID
        do {
            let recorder = SessionRecorder(try SessionFile.create(at: path, durability: .none))
            first = try recorder.append(.user("one"))
            try recorder.append(.assistant("reply"))
            try recorder.moveLeaf(to: first)
            #expect(recorder.tree.leaf == first && recorder.tree.entries.count == 2)
        }
        let reopened = try SessionFile.open(at: path, durability: .none)
        #expect(reopened.tree.leaf == first && reopened.tree.entries.count == 2)
    }

    @Test func `going back to nothing starts again from a root`() throws {
        let recorder = SessionRecorder(try SessionFile.create(at: path, durability: .none))
        try recorder.append(.user("one"))
        try recorder.moveLeaf(to: nil)
        let second = try recorder.append(.user("again"))
        #expect(recorder.tree.entry(second)?.parentID == nil)
    }

    @Test func `an entry that is not there is refused and changes nothing`() throws {
        let recorder = SessionRecorder(try SessionFile.create(at: path, durability: .none))
        let first = try recorder.append(.user("one"))
        #expect(throws: SessionFileError.self) { try recorder.moveLeaf(to: EntryID("nope")) }
        #expect(recorder.tree.leaf == first)
    }
}
