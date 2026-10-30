import AskAgentCore
import Foundation
import Testing

@testable import AskTools

/// The files the `@` picker offers (roadmap 0048, ADR-0069): git's own list in a repository, a bounded walk elsewhere, and only what the
/// sandbox lets ask read, with the rest counted and not named.
@Suite("The project's files are listed the way git sees them, and only what ask may read")
struct ProjectListerTests {
    /// A throwaway directory, removed when `body` returns.
    private func project(_ files: [String: String], body: (String) async throws -> Void) async throws {
        let made = FileManager.default.temporaryDirectory.appending(path: "ask-lister-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: made) }
        try FileManager.default.createDirectory(at: made, withIntermediateDirectories: true)
        let root = String(cString: realpath(made.path, nil))  // /var is a symbolic link to /private/var
        for (path, text) in files {
            let url = URL(filePath: root + "/" + path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url)
        }
        try await body(root)
    }

    /// Long enough for a cold `/usr/bin/git` on a CI runner: these tests are about what git lists, not about the fallback (CI took more
    /// than the 5 s ask allows, and the walk's listing was checked instead).
    private static let gitWait = Duration.seconds(60)

    private func git(_ arguments: [String], in root: String) throws {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/git")
        process.arguments = ["-c", "user.email=t@t", "-c", "user.name=t", "-c", "commit.gpgsign=false"] + arguments
        process.currentDirectoryURL = URL(filePath: root)
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0, "git \(arguments)")
    }

    @Test func `a repository lists tracked and untracked files, and not what is ignored or what git itself keeps`()
        async throws
    {
        try await project([
            "a.txt": "a", "src/b.swift": "b", ".gitignore": "out/\n*.log\n", "out/gen.txt": "x", "run.log": "x",
            "new/untracked.md": "u"
        ]) { root in
            try git(["init", "-q"], in: root)
            try git(["add", "a.txt", "src/b.swift", ".gitignore"], in: root)
            let listing = await ProjectLister.list(in: root, policy: .unrestricted, gitWait: Self.gitWait)
            #expect(listing.paths == [".gitignore", "a.txt", "new/untracked.md", "src/b.swift"])
            #expect(listing.hidden == 0 && !listing.truncated)
        }
    }

    @Test func `a tracked file that was deleted from disk is not offered`() async throws {
        try await project(["keep.txt": "k", "gone.txt": "g"]) { root in
            try git(["init", "-q"], in: root)
            try git(["add", "."], in: root)
            try FileManager.default.removeItem(atPath: root + "/gone.txt")
            #expect(
                await ProjectLister.list(in: root, policy: .unrestricted, gitWait: Self.gitWait).paths == ["keep.txt"])
        }
    }

    @Test func `outside a repository a walk lists the files, dotfiles included, and skips build output and tooling`()
        async throws
    {
        try await project([
            "README.md": "r", ".config/tool.json": "{}", "src/main.swift": "m", "node_modules/x/index.js": "j",
            ".build/debug/a.o": "o",
            "build/out.bin": "b", ".DS_Store": "s", ".git/config": "g"
        ]) { root in
            let listing = await ProjectLister.list(in: root, policy: .unrestricted, gitWait: Self.gitWait)
            #expect(listing.paths == [".config/tool.json", "README.md", "src/main.swift"])
        }
    }

    @Test func `a file the sandbox does not let ask read is counted and its name is not offered`() async throws {
        try await project(["open.txt": "o", "secret/key.pem": "k", "secret/also.txt": "a"]) { root in
            let policy = SandboxPolicy(denyRead: [SandboxRule(root + "/secret", .subpath)])
            let listing = await ProjectLister.list(in: root, policy: policy)
            #expect(listing.paths == ["open.txt"] && listing.hidden == 2)
        }
    }

    @Test func `a listing stops at its limit and says so`() async throws {
        try await project(Dictionary(uniqueKeysWithValues: (0 ..< 12).map { ("f\($0).txt", "x") })) { root in
            let listing = await ProjectLister.list(in: root, policy: .unrestricted, limit: 5)
            #expect(listing.paths.count == 5 && listing.truncated)
            #expect(await ProjectLister.list(in: root, policy: .unrestricted, limit: 12).truncated == false)
        }
    }

    @Test func `a tracked link to a directory is not a file and is not offered`() async throws {
        try await project(["real/a.txt": "a", "plain.txt": "p"]) { root in
            try FileManager.default.createSymbolicLink(atPath: root + "/link", withDestinationPath: "real")
            try git(["init", "-q"], in: root)
            try git(["add", "."], in: root)
            #expect(
                await ProjectLister.list(in: root, policy: .unrestricted, gitWait: Self.gitWait).paths == [
                    "plain.txt", "real/a.txt"
                ])
        }
    }

    @Test func `a path listed twice, as git does for a file in a merge conflict, is offered once`() async throws {
        try await project(["a.txt": "a", "b.txt": "b"]) { root in
            let listing = ProjectLister.readable(
                ["b.txt", "a.txt", "b.txt", "a.txt", "a.txt"], in: root, policy: .unrestricted, limit: 10)
            #expect(listing.paths == ["a.txt", "b.txt"] && listing.hidden == 0)
        }
    }

    @Test func `a directory that does not exist lists nothing and does not fail`() async {
        let listing = await ProjectLister.list(in: "/nonexistent-\(UUID().uuidString)", policy: .unrestricted)
        #expect(listing == ProjectListing())
    }

    @Test func `a path with spaces or non-ASCII characters survives git's NUL-separated list`() async throws {
        try await project(["with space/日本語 file.txt": "x", "plain.txt": "p"]) { root in
            try git(["init", "-q"], in: root)
            #expect(
                await ProjectLister.list(in: root, policy: .unrestricted, gitWait: Self.gitWait).paths == [
                    "plain.txt", "with space/日本語 file.txt"
                ])
        }
    }
}
