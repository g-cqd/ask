internal import Foundation
import Testing

/// The source standards leave out a file litmus has rewritten for a run: its schema lengthens the file and reads the process's
/// environment, so the suite would fail with no mutant active (2026-11-08 with the tool before it, AskAgentCore; 2026-11-16 with
/// litmus's declarations appended to every file: the ceiling and the executable's environment rule failed).
@Suite("A file the mutation tool rewrote is not held to the source standards")
struct MutationRewriteTests {
    @Test func `the tool's marker is recognised, and ordinary text is not`() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "mutation-rewrite-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let rewritten = directory.appending(path: "Rewritten.swift")
        let plain = directory.appending(path: "Plain.swift")
        // The first declaration litmus 0.3.2 appends to a file it rewrites, as its SchemaWriter writes it.
        let appended = "nonisolated private let __litmus_0123456789abcdef: Swift.String = \"\"\n"
        try Data(appended.utf8).write(to: rewritten)
        try Data("enum Plain {}\n".utf8).write(to: plain)
        #expect(SourceStandards.isMutationRewrite(rewritten))
        #expect(!SourceStandards.isMutationRewrite(plain))
    }
}
