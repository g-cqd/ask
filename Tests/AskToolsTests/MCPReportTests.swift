import Testing

@testable import AskTools

/// What `/mcp` says, and what a one-shot run says when a server did not start (ADR-0099).
@Suite("The servers' state is told in a line each, and only the ones that need attention are problems")
struct MCPReportTests {
    private func status(_ name: String, _ state: MCPServerStatus.State, notes: [String] = []) -> MCPServerStatus {
        MCPServerStatus(name: name, state: state, notes: notes)
    }

    @Test func `each state is a line that says what it is`() {
        #expect(MCPReport.lines([status("a", .off)]) == ["a: off (enabled is false in the configuration)"])
        #expect(MCPReport.lines([status("a", .connecting)]) == ["a: connecting…"])
        #expect(MCPReport.lines([status("a", .ready(offered: 3, of: 5))]) == ["a: ready, 3 of 5 tools offered"])
        #expect(MCPReport.lines([status("a", .ready(offered: 1, of: 1))]) == ["a: ready, 1 of 1 tool offered"])
        #expect(
            MCPReport.lines([status("a", .skipped("has 40 tools"))]) == ["a: connected, no tools offered: has 40 tools"]
        )
        #expect(MCPReport.lines([status("a", .failed("no thanks"))]) == ["a: not connected: no thanks"])
    }

    @Test func `a note follows its server's line, indented`() {
        #expect(
            MCPReport.lines([status("a", .ready(offered: 1, of: 2), notes: ["listed but missing: x"])])
                == ["a: ready, 1 of 2 tools offered", "    listed but missing: x"])
    }

    @Test func `no servers says how to add one`() {
        #expect(MCPReport.lines([]).count == 1 && MCPReport.lines([])[0].contains("\"mcp\""))
    }

    @Test func `a failure and a skip are problems, and nothing else is`() {
        #expect(status("a", .failed("boom")).problem == "MCP server a did not start: boom")
        #expect(
            status("a", .skipped("has 40 tools")).problem == "MCP server a has 40 tools; none of its tools are offered")
        for state: MCPServerStatus.State in [.off, .connecting, .ready(offered: 1, of: 1)] {
            #expect(status("a", state).problem == nil)
        }
    }
}
