import AskAI
import AskMCP
import Foundation

/// The suite passes the server's URL last and names the scenario in `MCP_CONFORMANCE_SCENARIO`. Every scenario the client knows runs
/// the same well-behaved session: start, list the tools, call the first with `{a: 2, b: 3}`, close. A failure exits 1, which the suite
/// records; it judges the rest from the traffic.
@main
struct ConformanceClient {
    static func main() async {
        guard let address = CommandLine.arguments.last, let url = URL(string: address) else {
            FileHandle.standardError.write(Data("usage: mcp-conformance-client URL\n".utf8))
            exit(2)
        }
        do {
            try await session(url)
        } catch {
            FileHandle.standardError.write(Data("failed: \(error)\n".utf8))
            exit(1)
        }
    }

    static func session(_ url: URL) async throws {
        let transport = try HTTPMCPTransport(url: url, userAgent: "ask-conformance", http: URLSessionTransport())
        let connection = MCPConnection(transport: transport, clientName: "ask-conformance", clientVersion: "1")
        _ = try await connection.start()
        let tools = try await connection.listTools()
        if let tool = tools.first {
            let arguments = try JSONObject(validating: Array(#"{"a":2,"b":3}"#.utf8))
            _ = try await connection.callTool(tool.name, arguments: arguments)
        }
        await connection.close()
    }
}
