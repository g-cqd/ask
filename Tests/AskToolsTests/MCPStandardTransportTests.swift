import AskAI
import AskAgentCore
import AskMCP
import Foundation
import Testing

@testable import AskTools

/// Which transport a server's setting gets (ADR-0099): the factory is thin, and what it must get right is the choice and the refusal.
@Suite("A setting with a command gets a process, a setting with a url gets HTTP, and an unsafe address gets neither")
struct MCPStandardTransportTests {
    private let factory = MCPHub.standardTransport(inheriting: ["PATH": "/usr/bin:/bin"])

    @Test func `a command is a process, which ends when closed`() async throws {
        let transport = try factory(MCPServerSetting(name: "a", command: "cat"), [:], [:])
        let process = try #require(transport as? StdioTransport)
        await process.close()
        #expect(process.exit == .exited(0))
    }

    @Test func `a url is an HTTP transport`() throws {
        let transport = try factory(MCPServerSetting(name: "a", url: "https://example.test/mcp"), [:], [:])
        #expect(transport is HTTPMCPTransport)
    }

    @Test func `a credential to a plain http address on another machine is refused`() {
        #expect(throws: MCPError.self) {
            _ = try factory(
                MCPServerSetting(name: "a", url: "http://example.test/mcp"), [:], ["Authorization": "Bearer x"])
        }
    }

    @Test func `a setting with neither a command nor an address is refused`() {
        #expect(throws: MCPError.self) { _ = try factory(MCPServerSetting(name: "a"), [:], [:]) }
    }
}
