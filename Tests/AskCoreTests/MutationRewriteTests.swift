internal import Foundation
import Testing

/// The source standards leave out a file swift-mutation-testing has rewritten for a run: its schemata lengthen the file and declare a
/// type of the tool's, so the unmutated suite failed and the scheduled run stopped (2026-11-08, AskAgentCore).
@Suite("A file the mutation tool rewrote is not held to the source standards")
struct MutationRewriteTests {
    @Test func `the tool's marker is recognised, and ordinary text is not`() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "mutation-rewrite-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let rewritten = directory.appending(path: "Rewritten.swift")
        let plain = directory.appending(path: "Plain.swift")
        try Data("enum \(SourceStandards.mutationMarker)b09f {}\n".utf8).write(to: rewritten)
        try Data("enum Plain {}\n".utf8).write(to: plain)
        #expect(SourceStandards.isMutationRewrite(rewritten))
        #expect(!SourceStandards.isMutationRewrite(plain))
    }
}
