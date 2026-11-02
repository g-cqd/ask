import AskAI
import AskAgentCore
import AskMCP
import Synchronization
import Testing

@testable import AskTools

/// Roadmap 0067, phase 4: a server's progress for a call reaches the run's reporter as one short line; with no one to tell, the call
/// asks the server for none.
@Suite("A server's progress for a call is told to the run, as a short line", .timeLimit(.minutes(1)))
struct MCPProgressTests {
    private let world = MCPWorld()

    private func calling(_ fake: FakeMCPServer, reporter: ToolProgressReporter?) async throws -> ToolOutput {
        let host = world.host([world.setting("srv")], ["srv": fake])
        host.start()
        await host.waitUntilSettled()
        defer { Task { await host.stop() } }
        let context = ToolContext(workingDirectory: "/tmp", progress: reporter).during(call: "c1")
        return try await world.call("mcp__srv__index", in: context)
    }

    @Test func `each report is a line: a share of a total, a count, and the server's words`() async throws {
        let fake = FakeMCPServer(tools: ["index"])
        fake.reportProgress([
            #""progress":1,"total":4,"message":"reading files""#, #""progress":12"#, #""progress":0.5,"message":"x""#,
            #""progress":3,"total":0"#
        ])
        let seen = Mutex<[String]>([])
        let output = try await calling(fake, reporter: { call, text in seen.withLock { $0.append("\(call) \(text)") } })
        #expect(output == ToolOutput("ran index"))
        #expect(seen.withLock { $0 } == ["c1 25% · reading files", "c1 12", "c1 x", "c1 3"])
        #expect(fake.progressAsked == 1)
    }

    @Test func `with no reporter the call asks for no progress`() async throws {
        let fake = FakeMCPServer(tools: ["index"])
        fake.reportProgress([#""progress":1"#])
        #expect(try await calling(fake, reporter: nil) == ToolOutput("ran index"))
        #expect(fake.progressAsked == 0)
    }

    @Test(arguments: [
        (MCPProgress(progress: 1, total: 3, message: nil), "33%"),
        (MCPProgress(progress: 9, total: 4, message: nil), "100%"),
        (MCPProgress(progress: -1, total: 4, message: nil), "0%"),
        (MCPProgress(progress: 2.5, total: nil, message: nil), "2.5"),
        (MCPProgress(progress: 1, total: nil, message: "  many\nlines  "), "many lines"),
        (
            MCPProgress(progress: 1, total: nil, message: String(repeating: "a", count: 90)),
            String(repeating: "a", count: 47) + "…"
        )
    ])
    func `a report reads short`(progress: MCPProgress, line: String) {
        #expect(MCPProgressLine.of(progress) == line)
    }
}
