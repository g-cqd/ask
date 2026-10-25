import AskAgentCore
import Foundation
import Testing

@testable import AskTools

/// What a focused job's lane reads: the end of the file the job writes, whole lines, with a cut said.
@Suite("A job's output tail is the end of its file, from a whole line, with the cut said", .timeLimit(.minutes(1)))
struct JobOutputTailTests {
    private func run(_ command: String, printed: String) async throws -> (JobTable, URL) {
        let root = FileManager.default.temporaryDirectory.appending(path: "ask-tail-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let table = JobTable()
        let seen = Printed(printed)
        _ = table.start(
            command, in: ToolContext(workingDirectory: root.path, outputDirectory: root.path), keepsInputOpen: true,
            keeping: 1_000, observe: { seen.received($0) })
        await seen.seen()
        return (table, root)
    }

    @Test func `a short output is returned whole`() async throws {
        let (table, root) = try await run("echo one; echo two; echo END; read hold", printed: "END")
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(table.outputTail(of: "job-1", maximumBytes: 1_000) == "one\ntwo\nEND\n")
        await table.stopAll()
    }

    @Test func `a long output is cut to the end on a line boundary and says so`() async throws {
        let (table, root) = try await run(
            "for i in 1 2 3 4 5 6 7 8 9 10; do echo line-$i; done; echo END; read hold", printed: "END")
        defer { try? FileManager.default.removeItem(at: root) }
        let tail = try #require(table.outputTail(of: "job-1", maximumBytes: 20))
        #expect(tail.hasPrefix("… earlier output not shown\n"))
        #expect(tail.hasSuffix("line-10\nEND\n") && !tail.contains("line-1\n"))
        for line in tail.split(separator: "\n").dropFirst() { #expect(line.hasPrefix("line-") || line == "END") }
        await table.stopAll()
    }

    @Test func `an unknown job, or one with no output file, has no tail`() async throws {
        let table = JobTable()
        #expect(table.outputTail(of: "job-9", maximumBytes: 100) == nil)
    }
}
