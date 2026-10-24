import AskAgentCore
import Darwin
import Foundation
import Synchronization
import Testing

@testable import AskTools

/// The agent's file write replaces a file by renaming a new one over it; found by `fcheck` (`replace-not-durable`) to flush neither the
/// bytes before the rename nor the directory after it (roadmap 0060, ADR-0089).
@Suite("The agent's file write is made durable before and after its rename")
struct FileToolsDurabilityTests {
    /// The flushes a test saw, in order.
    private final class Events: Sendable {
        private let log = Mutex<[String]>([])
        func add(_ event: String) { log.withLock { $0.append(event) } }
        var all: [String] { log.withLock { $0 } }
    }

    private let world: SandboxWorld
    private var target: String { world.workspace + "/target.txt" }

    init() throws { world = try SandboxWorld() }

    private func recording(_ events: Events, failing: String? = nil) -> (Int32) -> Int32 {
        let target = target
        return { descriptor in
            var info = stat()
            fstat(descriptor, &info)
            let kind = info.st_mode & S_IFMT == S_IFDIR ? "directory" : "file"
            events.add("\(kind) while \((try? String(contentsOfFile: target, encoding: .utf8)) ?? "absent")")
            if kind == failing {
                errno = EIO
                return -1
            }
            return 0
        }
    }

    private func write(_ text: String, flush: @escaping (Int32) -> Int32) throws(ToolFailure) {
        try ScopedFile.write(
            Array(text.utf8), to: URL(filePath: target), shownAs: "target.txt", in: world.context, flush: flush)
    }

    @Test func `the bytes are flushed while the old file is still there, and the directory once the new one is`() throws
    {
        try Data("old".utf8).write(to: URL(filePath: target))
        let events = Events()
        try write("new", flush: recording(events))
        #expect(events.all == ["file while old", "directory while new"])
        #expect(try String(contentsOfFile: target, encoding: .utf8) == "new")
    }

    @Test func `a file that did not exist is flushed the same way`() throws {
        let events = Events()
        try write("new", flush: recording(events))
        #expect(events.all == ["file while absent", "directory while new"])
    }

    @Test func `when the bytes cannot be flushed the old file stays, no temporary is left, and the model is told`()
        throws
    {
        try Data("old".utf8).write(to: URL(filePath: target))
        let events = Events()
        #expect(throws: ToolFailure.self) { try write("new", flush: recording(events, failing: "file")) }
        #expect(try String(contentsOfFile: target, encoding: .utf8) == "old")
        #expect(
            try FileManager.default.contentsOfDirectory(atPath: world.workspace).sorted() == ["file.txt", "target.txt"])
    }

    @Test func `when the directory cannot be flushed the model is told, not left to think it is safe`() throws {
        try Data("old".utf8).write(to: URL(filePath: target))
        let events = Events()
        #expect(throws: ToolFailure.self) { try write("new", flush: recording(events, failing: "directory")) }
    }
}
