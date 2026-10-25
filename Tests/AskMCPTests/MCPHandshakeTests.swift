internal import AemiJSON
internal import AskAI
internal import Foundation
internal import Testing

@testable import AskMCP

/// The start of a connection: what the client offers, what it accepts, and what it sends once it is done (ADR-0096). The version
/// behaviour is what two real servers did (probes, diary 2026-10-25 (06)): one answers the version asked for, and one that does not know it
/// answers with its own latest.
@Suite("A connection negotiates a protocol version and announces itself ready", .timeLimit(.minutes(1)))
struct MCPHandshakeTests {
    private static let result = """
        {"protocolVersion":"2025-11-25","capabilities":{"tools":{"listChanged":true},"prompts":{},"logging":{}},\
        "serverInfo":{"name":"everything","title":"Everything","version":"2.0.1"},"instructions":"Use echo to echo."}
        """

    private func connect(answering result: String = result) -> (MCPConnection, ScriptedTransport) {
        let transport = ScriptedTransport()
        transport.on("initialize") { [$0.result(result)] }
        return (MCPConnection(transport: transport, clientName: "ask", clientVersion: "9.9"), transport)
    }

    @Test func `it offers the newest version it knows, no capabilities, and its own name`() async throws {
        let (connection, transport) = connect()
        _ = try await connection.start()
        let params = try #require(transport.sent("initialize").first?.params)
        let root = try AemiJSON.parse(Array(params.utf8)).root
        #expect(root["protocolVersion"].string == "2025-11-25")
        #expect(root["capabilities"].isObject && root["capabilities"].int == nil)
        #expect(root["clientInfo"]["name"].string == "ask" && root["clientInfo"]["version"].string == "9.9")
    }

    @Test func `it reports what the server said about itself, and says it is ready only after the answer`() async throws
    {
        let (connection, transport) = connect()
        let info = try await connection.start()
        #expect(info.protocolVersion == "2025-11-25" && info.name == "everything" && info.title == "Everything")
        #expect(info.version == "2.0.1" && info.instructions == "Use echo to echo.")
        #expect(info.supportsTools && info.toolsMayChange)
        #expect(transport.sent.map(\.method) == ["initialize", "notifications/initialized"])
    }

    @Test func `an older version the client knows is accepted`() async throws {
        let (connection, _) = connect(answering: Self.result.replacingOccurrences(of: "2025-11-25", with: "2024-11-05"))
        #expect(try await connection.start().protocolVersion == "2024-11-05")
    }

    @Test func `a version the client does not know ends the connection and says which`() async throws {
        let (connection, transport) = connect(
            answering: Self.result.replacingOccurrences(of: "2025-11-25", with: "2031-01-01"))
        await #expect(throws: MCPError.unsupportedVersion("2031-01-01")) { _ = try await connection.start() }
        #expect(transport.isClosed)
        #expect(transport.sent("notifications/initialized").isEmpty, "it never said it was ready")
    }

    @Test func `a server that refuses to start is reported with its own words`() async throws {
        let transport = ScriptedTransport()
        transport.on("initialize") { [$0.failure(-32602, "Unsupported protocol version")] }
        let connection = MCPConnection(transport: transport, clientName: "ask", clientVersion: "1")
        await #expect(throws: MCPError.rpc(code: -32602, message: "Unsupported protocol version")) {
            _ = try await connection.start()
        }
    }

    @Test
    func `a server with no tools capability is said to have none, and one without listChanged is said not to change`()
        async throws
    {
        let (connection, _) = connect(
            answering:
                #"{"protocolVersion":"2025-11-25","capabilities":{"tools":{}},"serverInfo":{"name":"s","version":"1"}}"#
        )
        let info = try await connection.start()
        #expect(info.supportsTools && !info.toolsMayChange && info.instructions == nil && info.title == nil)
        let (bare, _) = connect(
            answering: #"{"protocolVersion":"2025-11-25","capabilities":{},"serverInfo":{"name":"s","version":"1"}}"#)
        #expect(try await bare.start().supportsTools == false)
    }

    @Test func `a reply that is not a result at all is a malformed one, not a crash`() async throws {
        let (connection, _) = connect(answering: "[1,2,3]")
        await #expect(throws: MCPError.self) { _ = try await connection.start() }
    }

    @Test func `starting twice is refused rather than negotiating again`() async throws {
        let (connection, transport) = connect()
        _ = try await connection.start()
        await #expect(throws: MCPError.alreadyStarted) { _ = try await connection.start() }
        #expect(transport.sent("initialize").count == 1)
    }
}
