internal import AskAI
internal import Foundation
internal import Testing

@testable import AskMCP

/// A server that goes away, and a client that leaves.
@Suite("A connection that loses its server fails what was waiting and refuses what comes next", .timeLimit(.minutes(1)))
struct MCPDisconnectTests {
    private static let initResult =
        #"{"protocolVersion":"2025-11-25","capabilities":{"tools":{}},"serverInfo":{"name":"s","version":"1"}}"#

    private func started() async throws -> (MCPConnection, ScriptedTransport) {
        let transport = ScriptedTransport()
        transport.on("initialize") { [$0.result(Self.initResult)] }
        transport.on("tools/call") { _ in [] }
        let connection = MCPConnection(transport: transport, clientName: "ask", clientVersion: "1")
        _ = try await connection.start()
        return (connection, transport)
    }

    @Test func `a server that exits while a call waits fails that call, and says so as an event`() async throws {
        let (connection, transport) = try await started()
        var events = connection.events.makeAsyncIterator()
        let call = Task { try await connection.callTool("long", arguments: .empty) }
        await transport.waitUntilSent("tools/call")
        transport.end()
        await #expect(throws: MCPError.disconnected) { _ = try await call.value }
        #expect(await events.next() == .closed)
    }

    @Test func `after the server is gone nothing is sent, and every call fails at once`() async throws {
        let (connection, transport) = try await started()
        transport.end()
        var events = connection.events.makeAsyncIterator()
        #expect(await events.next() == .closed)
        let before = transport.sent.count
        await #expect(throws: MCPError.disconnected) { _ = try await connection.callTool("late", arguments: .empty) }
        await #expect(throws: MCPError.disconnected) { _ = try await connection.listTools() }
        #expect(transport.sent.count == before)
    }

    @Test func `closing from this side closes the transport, fails what waited, and is safe to do twice`() async throws
    {
        let (connection, transport) = try await started()
        let call = Task { try await connection.callTool("long", arguments: .empty) }
        await transport.waitUntilSent("tools/call")
        await connection.close()
        await connection.close()
        #expect(transport.isClosed)
        await #expect(throws: MCPError.disconnected) { _ = try await call.value }
    }

    @Test func `a call before start is refused, not sent`() async throws {
        let transport = ScriptedTransport()
        let connection = MCPConnection(transport: transport, clientName: "ask", clientVersion: "1")
        await #expect(throws: MCPError.notStarted) { _ = try await connection.listTools() }
        #expect(transport.sent.isEmpty)
    }

    @Test func `a message the transport cannot send fails the call it was for`() async throws {
        let transport = FailingTransport()
        let connection = MCPConnection(transport: transport, clientName: "ask", clientVersion: "1")
        await #expect(throws: MCPError.disconnected) { _ = try await connection.start() }
    }
}
