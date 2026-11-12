import AskAgentCore
import Foundation
import Synchronization
import Testing

@testable import AskTools

/// `#123` read from the workspace's GitHub repository (roadmap 0186): its `origin`, GitHub's issues API, `GITHUB_TOKEN` when set;
/// anything that fails leaves the reference as text.
@Suite("Reading #123 from GitHub")
struct ForgeReaderTests {
    private static func response(_ request: URLRequest, _ status: Int) -> URLResponse {
        let url = request.url ?? URL(fileURLWithPath: "/")
        return HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil) ?? URLResponse()
    }

    private func repository(origin: String?) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ask-forge-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var commands = [["init", "-q"]]
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

    @Test func `each number is read from the origin's repository, in order, with the token`() async throws {
        let directory = try repository(origin: "git@github.com:g-cqd/ask.git")
        defer { try? FileManager.default.removeItem(at: directory) }
        let asked = Mutex<[(String, String?)]>([])
        let items = await ForgeReader.items(
            for: "see #7 and #3",
            workspace: directory.path,
            token: "secret",
            path: ProcessInfo.processInfo.environment["PATH"]
        ) { request in
            asked.withLock {
                $0.append((request.url?.absoluteString ?? "", request.value(forHTTPHeaderField: "Authorization")))
            }
            let number = request.url?.lastPathComponent ?? ""
            let body =
                #"{"number":\#(number),"title":"T\#(number)","state":"open","html_url":"u","body":"b","user":{"login":"x"}}"#
            return (
                Data(body.utf8),
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            )  // swift-format-ignore
        }
        #expect(items.map(\.number) == [7, 3])
        let urls = asked.withLock { $0 }.map(\.0).sorted()
        #expect(
            urls == [
                "https://api.github.com/repos/g-cqd/ask/issues/3", "https://api.github.com/repos/g-cqd/ask/issues/7"
            ]
        )
        #expect(asked.withLock { $0 }.allSatisfy { $0.1 == "Bearer secret" })
    }

    @Test func `no GitHub origin, a failed read or no number: nothing is attached and nothing is asked`() async throws {
        let none = try repository(origin: nil)
        let other = try repository(origin: "https://gitlab.com/a/b.git")
        defer {
            try? FileManager.default.removeItem(at: none)
            try? FileManager.default.removeItem(at: other)
        }
        let asked = Mutex(0)
        let fetch: ForgeReader.Fetch = { request in
            asked.withLock { $0 += 1 }
            return (Data(), Self.response(request, 404))
        }
        let path = ProcessInfo.processInfo.environment["PATH"]
        #expect(await ForgeReader.items(for: "#1", workspace: none.path, token: nil, path: path, fetch: fetch).isEmpty)
        #expect(await ForgeReader.items(for: "#1", workspace: other.path, token: nil, path: path, fetch: fetch).isEmpty)
        #expect(
            await ForgeReader.items(for: "no number", workspace: other.path, token: nil, path: path, fetch: fetch)
                .isEmpty
        )
        #expect(asked.withLock { $0 } == 0)
        let github = try repository(origin: "https://github.com/a/b")
        defer { try? FileManager.default.removeItem(at: github) }
        #expect(
            await ForgeReader.items(for: "#1", workspace: github.path, token: nil, path: path, fetch: fetch).isEmpty
        )
        #expect(asked.withLock { $0 } == 1)
    }
}
