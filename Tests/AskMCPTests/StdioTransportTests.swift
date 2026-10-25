internal import AemiTesting
internal import AskAI
internal import Foundation
internal import Testing

@testable import AskMCP

/// The transport against a real process, a small MCP server in Python that can misbehave (`Fixtures/fixture-server.py`).
@Suite("A stdio transport carries a conversation with a child process and ends it", .timeLimit(.minutes(1)))
struct StdioTransportTests {
    private static let script = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appending(path: "Fixtures/fixture-server.py").path

    private func launch(
        _ mode: String = "", inheriting: [String: String] = ProcessInfo.processInfo.environment,
        adding: [String: String] = [:],
        directory: String? = nil
    ) -> StdioLaunch {
        StdioLaunch(
            executable: "python3", arguments: mode.isEmpty ? [Self.script] : [Self.script, mode], environment: adding,
            workingDirectory: directory, inheriting: inheriting)
    }

    private func connect(_ launch: StdioLaunch, clock: any Clock<Duration> = ContinuousClock()) -> (
        MCPConnection, StdioTransport
    ) {
        let transport = StdioTransport(launch, clock: clock)
        return (MCPConnection(transport: transport, clientName: "ask", clientVersion: "1"), transport)
    }

    private func text(_ result: MCPToolResult) -> String {
        result.content.compactMap { if case .text(let text) = $0 { text } else { nil } }.joined()
    }

    @Test func `a whole conversation: start, two pages of tools, a call, and a close that ends the process`()
        async throws
    {
        let (connection, transport) = connect(launch())
        let info = try await connection.start()
        #expect(info.name == "fixture" && info.supportsTools)
        #expect(try await connection.listTools().map(\.name) == ["echo", "env", "pwd", "big", "log"])
        let message = try JSONObject(validating: Array(#"{"message":"héllo"}"#.utf8))
        #expect(text(try await connection.callTool("echo", arguments: message)) == "Echo: héllo")
        await connection.close()
        #expect(transport.exit == .exited(0), "closing stdin is what a well-behaved server leaves on")
    }

    @Test func `the child sees only a minimal environment and what the configuration added`() async throws {
        let source = [
            "PATH": ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin", "HOME": "/Users/x",
            "ANTHROPIC_API_KEY": "sk-secret"
        ]
        let (connection, _) = connect(launch(inheriting: source, adding: ["CHOSEN": "yes"]))
        _ = try await connection.start()
        let names = text(try await connection.callTool("env", arguments: .empty)).split(separator: ",").map(String.init)
        await connection.close()
        #expect(names.contains("PATH") && names.contains("HOME") && names.contains("CHOSEN"))
        #expect(!names.contains("ANTHROPIC_API_KEY"))
    }

    @Test func `the child runs where it was told to`() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "mcp-cwd-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let (connection, _) = connect(launch(directory: directory.path))
        _ = try await connection.start()
        let reported = text(try await connection.callTool("pwd", arguments: .empty))
        await connection.close()
        #expect(
            URL(fileURLWithPath: reported).resolvingSymlinksInPath().path == directory.resolvingSymlinksInPath().path)
    }

    @Test func `what the child writes to stderr is kept apart, and never mistaken for a message`() async throws {
        let (connection, transport) = connect(launch())
        _ = try await connection.start()
        let args = try JSONObject(validating: Array(#"{"text":"a diagnostic"}"#.utf8))
        #expect(text(try await connection.callTool("log", arguments: args)) == "logged")
        await connection.close()
        #expect(transport.standardErrorTail.contains("a diagnostic"))
    }

    @Test func `a line that is not a message is reported, and the conversation goes on`() async throws {
        let (connection, _) = connect(launch("garbage"))
        var events = connection.events.makeAsyncIterator()
        _ = try await connection.start()
        #expect(try await connection.listTools().count == 5)
        guard case .malformed(let line)? = await events.next() else {
            Issue.record("no event for the stray line")
            return
        }
        #expect(line.contains("Server listening"))
        await connection.close()
    }

    @Test func `a message that arrives in pieces is put back together`() async throws {
        let (connection, _) = connect(launch("split"))
        _ = try await connection.start()
        #expect(try await connection.listTools().count == 5)
        await connection.close()
    }

    @Test func `a result of a megabyte arrives whole`() async throws {
        let (connection, _) = connect(launch())
        _ = try await connection.start()
        let args = try JSONObject(validating: Array(#"{"kilobytes":1024}"#.utf8))
        #expect(text(try await connection.callTool("big", arguments: args)).utf8.count == 1024 * 1024)
        await connection.close()
    }

    @Test func `a message longer than the limit ends the conversation instead of filling memory`() async throws {
        let transport = StdioTransport(launch(), maximumMessageBytes: 64 * 1024)
        let connection = MCPConnection(transport: transport, clientName: "ask", clientVersion: "1")
        _ = try await connection.start()
        let args = try JSONObject(validating: Array(#"{"kilobytes":1024}"#.utf8))
        await #expect(throws: MCPError.disconnected) { _ = try await connection.callTool("big", arguments: args) }
        await connection.close()
        #expect(transport.failure?.contains("longer than 65536") == true)
    }

    @Test func `a server that dies mid-call fails the call, and its exit is recorded`() async throws {
        let (connection, transport) = connect(launch("crash"))
        _ = try await connection.start()
        var events = connection.events.makeAsyncIterator()
        await #expect(throws: MCPError.disconnected) { _ = try await connection.callTool("echo", arguments: .empty) }
        while let event = await events.next(), event != .closed {}
        await connection.close()
        #expect(transport.exit == .exited(3))
    }

    @Test func `a program that cannot be started is an ended conversation with a reason, not a hang`() async throws {
        let (connection, transport) = connect(
            StdioLaunch(
                executable: "/nonexistent/mcp-server", arguments: [], environment: [:], workingDirectory: nil,
                inheriting: [:]))
        await #expect(throws: MCPError.disconnected) { _ = try await connection.start() }
        #expect(transport.failure?.isEmpty == false)
    }

    @Test func `a server that ignores end of input and the polite signal is made to leave, after the grace`()
        async throws
    {
        let clock = TestClock()
        let (connection, transport) = connect(launch("stubborn"), clock: clock)
        _ = try await connection.start()
        let closing = Task { await connection.close() }
        try await clock.waitForSleepers(count: 1)
        clock.advance(by: .seconds(2))
        await closing.value
        #expect(transport.exit != nil && transport.exit != .exited(0), "it did not leave on its own: it was stopped")
    }
}
