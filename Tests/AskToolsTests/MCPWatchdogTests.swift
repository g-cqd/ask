import AskAgentCore
import AskMCP
import Foundation
import Testing

@testable import AskTools

/// A server's process is on the watchdog's list while it runs (ADR-0102), so ask being killed does not leave it behind.
@Suite("A stdio server's process group is watched while it runs and released when it ends", .timeLimit(.minutes(1)))
struct MCPWatchdogTests {
    private let jobs = JobTable()

    private func launch(_ setting: MCPServerSetting) throws -> StdioTransport {
        let factory = MCPHub.standardTransport(inheriting: ["PATH": "/usr/bin:/bin"], jobs: jobs)
        return try #require(try factory(setting, [:], [:]) as? StdioTransport)
    }

    @Test func `a server that is running is on the list, and off it once it has ended`() async throws {
        let transport = try launch(MCPServerSetting(name: "a", command: "cat"))
        let pid = try #require(await transport.waitUntilRunning())
        #expect(jobs.watchdog.watching == [pid])
        await transport.close()
        #expect(jobs.watchdog.watching.isEmpty)
    }

    @Test func `a program that cannot start is never on the list`() async throws {
        let transport = try launch(MCPServerSetting(name: "a", command: "/nonexistent/mcp-server"))
        #expect(await transport.waitUntilRunning() == nil)
        await transport.close()
        #expect(jobs.watchdog.watching.isEmpty)
    }

    @Test func `without a job table there is no list, and a server still runs`() async throws {
        let factory = MCPHub.standardTransport(inheriting: ["PATH": "/usr/bin:/bin"])
        let transport = try #require(
            try factory(MCPServerSetting(name: "a", command: "cat"), [:], [:]) as? StdioTransport)
        #expect(await transport.waitUntilRunning() != nil)
        await transport.close()
        #expect(jobs.watchdog.watching.isEmpty)
    }

    @Test func `when ask dies the shell stops a server that ignores its input closing and the polite signal`()
        async throws
    {
        let stubborn = try launch(
            MCPServerSetting(
                name: "a", command: "sh",
                args: ["-c", "trap '' TERM; exec 0<&-; while true; do sleep 1; done"]))
        let pid = try #require(await stubborn.waitUntilRunning())
        await jobs.watchdog.waitForProtection { $0 != .idle && $0 != .starting }
        jobs.watchdog.simulateDeath()
        #expect(try await ProcessExit.observed(pid), "the watchdog's shell sent SIGTERM, waited, and then sent SIGKILL")
        await stubborn.close()
    }
}
