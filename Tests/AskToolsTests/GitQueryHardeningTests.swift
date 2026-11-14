import Foundation
import Testing

@testable import AskTools

/// The git commands ask runs by itself (the status bar's segment, the forge's repository and branch) run before the person approved
/// anything, in a folder whose `.git` may not be theirs (an archive unpacked, a folder shared). A repository's own configuration can
/// make `git status` run a command: `core.fsmonitor`, and a `filter` named by `.gitattributes` (security audit 3, 2026-11-13). Neither
/// may run.
@Suite("ask's own git queries run nothing a repository's configuration names")
struct GitQueryHardeningTests {
    private func git(_ arguments: [String], in directory: URL) throws {
        let git = Process()
        git.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        git.arguments =
            ["-C", directory.path, "-c", "core.hooksPath=/dev/null", "-c", "user.name=t", "-c", "user.email=t@t"]
            + arguments
        git.standardOutput = FileHandle.nullDevice
        git.standardError = FileHandle.nullDevice
        try git.run()
        git.waitUntilExit()
    }

    /// A repository with one committed file, changed since without changing its size, whose configuration runs `touch MARKER` as
    /// its file-system monitor and as the clean filter of every file.
    private func hostileRepository() throws -> (directory: URL, marker: String) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "ask-hostile-\(UUID().uuidString)"
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let marker = directory.appendingPathComponent("RAN").path
        try git(["init", "-q", "-b", "work"], in: directory)
        try "aaaa\n".write(to: directory.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)
        try "* filter=hostile\n"
            .write(to: directory.appendingPathComponent(".gitattributes"), atomically: true, encoding: .utf8)
        try git(["add", "."], in: directory)
        try git(["commit", "-q", "-m", "one"], in: directory)
        try git(["config", "core.fsmonitor", "sh -c 'touch \(marker); exit 1'"], in: directory)
        try git(["config", "filter.hostile.clean", "sh -c 'touch \(marker); cat'"], in: directory)
        // The same size at a later time: git must read the content to tell, which is when a clean filter runs.
        try "bbbb\n".write(to: directory.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)
        let later = Date().addingTimeInterval(5)
        try FileManager.default.setAttributes(
            [.modificationDate: later],
            ofItemAtPath: directory.appendingPathComponent("file.txt").path
        )
        return (directory, marker)
    }

    @Test func `the status, the branch and the remote are read, and neither the monitor nor the filter runs`()
        async throws
    {
        let (directory, marker) = try hostileRepository()
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = ProcessInfo.processInfo.environment["PATH"]
        let forms = await GitStatus.read(in: directory.path, path: path)
        #expect(forms.first == "work · 1 changed", "the change is still seen: \(forms)")
        #expect(await ForgeReader.currentBranch(workspace: directory.path, path: path) == "work")
        _ = await ForgeReader.openItems(workspace: directory.path, token: nil, path: path) { _ in
            throw CancellationError()
        }
        #expect(!FileManager.default.fileExists(atPath: marker), "the repository's configuration ran a command")
    }

    @Test func `the fixture is hostile: a plain git status runs it`() throws {
        let (directory, marker) = try hostileRepository()
        defer { try? FileManager.default.removeItem(at: directory) }
        try git(["status", "--porcelain"], in: directory)
        #expect(FileManager.default.fileExists(atPath: marker), "without this the test above proves nothing")
    }
}
