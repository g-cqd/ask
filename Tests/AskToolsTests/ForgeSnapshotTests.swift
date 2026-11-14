import Foundation
import Testing

@testable import AskTools

/// The workspace's repository as ask shows it, read in one go so that a child process can do it (ADR-0152).
@Suite("A forge snapshot is read here or by a child, and says the same")
struct ForgeSnapshotTests {
    private let path = ProcessInfo.processInfo.environment["PATH"]

    private func repository(origin: String?) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "ask-snapshot-\(UUID().uuidString)"
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var commands = [["init", "-q", "-b", "work"]]
        if let origin { commands.append(["remote", "add", "origin", origin]) }
        for arguments in commands {
            let git = Process()
            git.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            git.arguments = ["-C", directory.path] + arguments
            try git.run()
            git.waitUntilExit()
        }
        return directory
    }

    /// A script standing for `ask`: it records its arguments and its token, then does `body`.
    private func executable(in directory: URL, _ body: String) throws -> String {
        let file = directory.appendingPathComponent("fake-ask")
        let script = """
            #!/bin/sh
            printf '%s\\n' "$@" > "\(directory.path)/arguments"
            printf '%s' "${GITHUB_TOKEN-unset}" > "\(directory.path)/token"
            \(body)
            """
        try script.write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        return file.path
    }

    private func said(_ name: String, in directory: URL) -> String? {
        try? String(contentsOf: directory.appendingPathComponent(name), encoding: .utf8)
    }

    @Test func `read here: the open items as the picker lists them, and the branch's pull request`() async throws {
        let directory = try repository(origin: "https://github.com/g-cqd/ask.git")
        defer { try? FileManager.default.removeItem(at: directory) }
        let snapshot = await ForgeSnapshot.read(workspace: directory.path, token: nil, path: path) { request in
            let url = request.url?.absoluteString ?? ""
            let body =
                url.contains("/pulls?state=open&head=g-cqd:work&")
                ? #"[{"number":42,"title":"Work","state":"open"}]"#
                : #"[{"number":42,"title":"Work","state":"open","pull_request":{}},{"number":7,"title":"Bug","state":"open"}]"#
            return (
                Data(body.utf8),
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            )  // swift-format-ignore
        }
        #expect(
            snapshot
                == ForgeSnapshot(
                    open: [
                        .init(number: 42, kind: "pull request", title: "Work"),
                        .init(number: 7, kind: "issue", title: "Bug")
                    ],
                    pullRequest: 42
                )
        )
    }

    @Test func `a snapshot survives its JSON, and what is not one is nothing`() {
        let snapshot = ForgeSnapshot(
            open: [.init(number: 7, kind: "issue", title: "A \"title\"\nin two lines")],
            pullRequest: 3
        )
        #expect(ForgeSnapshot(json: snapshot.encoded()) == snapshot)
        #expect(!snapshot.encoded().contains(0x0A), "one line")
        #expect(ForgeSnapshot(json: ForgeSnapshot().encoded()) == ForgeSnapshot())
        #expect(ForgeSnapshot(json: Array("not json".utf8)) == nil)
        #expect(ForgeSnapshot(json: Array("[]".utf8)) == nil)
        #expect(ForgeSnapshot(json: []) == nil)
    }

    @Test func `read by a child: it is told the workspace, and the token in its environment only`() async throws {
        let directory = try repository(origin: "git@github.com:g-cqd/ask.git")
        defer { try? FileManager.default.removeItem(at: directory) }
        let printed = #"{"open":[{"number":7,"kind":"issue","title":"Bug"}],"pullRequest":42}"#
        let child = try executable(in: directory, "printf '%s\\n' '\(printed)'")
        let snapshot = await ForgeSnapshot.read(by: child, workspace: directory.path, token: "secret", path: path)
        #expect(snapshot == ForgeSnapshot(open: [.init(number: 7, kind: "issue", title: "Bug")], pullRequest: 42))
        #expect(said("arguments", in: directory) == "forge\n\(directory.path)\n")
        #expect(said("token", in: directory) == "secret")
        _ = await ForgeSnapshot.read(by: child, workspace: directory.path, token: nil, path: path)
        #expect(said("token", in: directory) == "unset", "no token is none, not an empty one")
    }

    @Test func `a child that fails, prints something else or takes too long gives nothing`() async throws {
        let directory = try repository(origin: "https://github.com/g-cqd/ask")
        defer { try? FileManager.default.removeItem(at: directory) }
        let failing = try executable(in: directory, "echo '{\"open\":[]}'; exit 3")
        #expect(await ForgeSnapshot.read(by: failing, workspace: directory.path, token: nil, path: path) == nil)
        let other = try executable(in: directory, "echo usage: something else")
        #expect(await ForgeSnapshot.read(by: other, workspace: directory.path, token: nil, path: path) == nil)
        let slow = try executable(in: directory, "exec sleep 30")
        let late = await ForgeSnapshot.read(
            by: slow,
            workspace: directory.path,
            token: nil,
            path: path,
            deadline: .milliseconds(200)
        )
        #expect(late == nil)
        let missing = directory.appendingPathComponent("no-such-program").path
        #expect(await ForgeSnapshot.read(by: missing, workspace: directory.path, token: nil, path: path) == nil)
    }

    @Test func `a workspace that is not on GitHub starts no child and is empty`() async throws {
        for origin in [nil, "https://gitlab.com/a/b.git"] {
            let directory = try repository(origin: origin)
            defer { try? FileManager.default.removeItem(at: directory) }
            let child = try executable(in: directory, "echo '{\"open\":[],\"pullRequest\":9}'")
            let snapshot = await ForgeSnapshot.read(by: child, workspace: directory.path, token: "secret", path: path)
            #expect(snapshot == ForgeSnapshot())
            #expect(said("arguments", in: directory) == nil, "the child was not run")
        }
    }
}
