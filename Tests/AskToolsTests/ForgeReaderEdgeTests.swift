import AskAI
import AskAgentCore
import Foundation
import Synchronization
import Testing

@testable import AskTools

/// The edges of `ForgeReader` the mutation run found untested (2026-11-13).
@Suite("ForgeReader's branch and its pull request")
struct ForgeReaderEdgeTests {
    private func git(_ arguments: [String], in directory: URL) throws {
        let git = Process()
        git.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        git.arguments = ["-C", directory.path] + arguments
        git.standardOutput = FileHandle.nullDevice
        git.standardError = FileHandle.nullDevice
        try git.run()
        git.waitUntilExit()
    }

    @Test func `the current branch, none when detached or outside a repository`() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ask-branch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = ProcessInfo.processInfo.environment["PATH"]
        #expect(await ForgeReader.currentBranch(workspace: directory.path, path: path) == nil)
        try git(["init", "-q", "-b", "work"], in: directory)
        #expect(await ForgeReader.currentBranch(workspace: directory.path, path: path) == "work")
        try git(
            ["-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "--allow-empty", "-m", "x"],
            in: directory
        )
        try git(["checkout", "-q", "--detach"], in: directory)
        #expect(await ForgeReader.currentBranch(workspace: directory.path, path: path) == nil)
    }

    @Test func `a branch name that would change the query asks nothing`() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ask-branch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try git(["init", "-q"], in: directory)
        try git(["remote", "add", "origin", "https://github.com/o/r.git"], in: directory)
        let asked = Mutex(0)
        let fetch: ForgeReader.Fetch = { request in
            asked.withLock { $0 += 1 }
            let reply = HTTPURLResponse(
                url: request.url ?? URL(fileURLWithPath: "/"),
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )
            return (
                Data(#"[{"number":4,"title":"t","state":"open","html_url":"u","user":{"login":"x"}}]"#.utf8),
                reply ?? URLResponse()
            )
        }
        let path = ProcessInfo.processInfo.environment["PATH"]
        for refused in ["a&b", "a b", "a#b", "a?b", "a%b", ""] {
            #expect(
                await ForgeReader.branchPullRequest(
                    branch: refused,
                    workspace: directory.path,
                    token: nil,
                    path: path,
                    fetch: fetch
                ) == nil
            )
        }
        #expect(asked.withLock { $0 } == 0)
        #expect(
            await ForgeReader.branchPullRequest(
                branch: "ok",
                workspace: directory.path,
                token: nil,
                path: path,
                fetch: fetch
            ) == 4
        )
    }

    @Test func `search: an empty query is an error, no hits says so`() async {
        let tool = SessionSearchTool { nil }
        let empty = await tool.run(
            try! JSONObject(validating: Array(#"{"query":""}"#.utf8)),
            in: ToolContext(workingDirectory: "/tmp")
        )
        #expect(empty.isError)
        #expect(SessionSearchTool.text(of: [], query: "zlib") == "Nothing found for zlib.")
    }
}
