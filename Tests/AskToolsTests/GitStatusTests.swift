import Foundation
import Testing

@testable import AskTools

/// The workspace's git state for the status bar (roadmap 0186, the owner's answer of 2026-11-12: at the end of the status bar): one
/// `git status --porcelain=v2 --branch`, shown whole, shorter, or as the branch alone.
@Suite("The status bar's git segment")
struct GitStatusTests {
    @Test func `a branch ahead and behind with changes reads in three forms`() {
        let porcelain = """
            # branch.oid 0123
            # branch.head main
            # branch.upstream origin/main
            # branch.ab +2 -1
            1 .M N... 100644 100644 100644 a b Sources/a.swift
            2 R. N... 100644 100644 100644 a b R100 new.swift\told.swift
            ? notes.txt
            ! ignored.o
            """
        #expect(GitStatus.forms(porcelain: porcelain) == ["main ↑2 ↓1 · 3 changed", "main ↑2↓1 ·3", "main"])
    }

    @Test func `a clean branch level with its upstream is its name alone`() {
        #expect(GitStatus.forms(porcelain: "# branch.head topic\n# branch.ab +0 -0\n") == ["topic"])
    }

    @Test func `a detached head and a branch with no upstream`() {
        #expect(
            GitStatus.forms(porcelain: "# branch.head (detached)\n# branch.oid abcdef1234\n? x\n") == [
                "abcdef1 · 1 changed", "abcdef1 ·1", "abcdef1"
            ]
        )
        #expect(GitStatus.forms(porcelain: "# branch.head new\n") == ["new"])
    }

    @Test func `outside a repository there is no segment`() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ask-git-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(await GitStatus.read(in: directory.path, path: ProcessInfo.processInfo.environment["PATH"]).isEmpty)
    }

    @Test func `in a repository it reads the branch and the changes`() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ask-git-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let git = Process()
        git.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        git.arguments = ["-C", directory.path, "init", "-q", "-b", "work"]
        try git.run()
        git.waitUntilExit()
        try "x".write(to: directory.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        #expect(
            await GitStatus.read(in: directory.path, path: ProcessInfo.processInfo.environment["PATH"]) == [
                "work · 1 changed", "work ·1", "work"
            ]
        )
    }
}
