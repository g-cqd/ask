import Foundation
import Testing

@testable import AskAI

/// An MCP server's sign-in is kept with the providers' (roadmap 0067): one record per server, its tokens secrets like theirs, so a
/// keychain keeps them out of the file.
@Suite("An MCP server's sign-in is stored beside the providers', its tokens as secrets")
struct MCPCredentialStorageTests {
    private static let record = MCPServerCredentials(
        server: "https://mcp.example.com/mcp",
        issuer: "https://auth.example.com",
        tokenEndpoint: "https://auth.example.com/token",
        clientID: "client-1",
        redirectURI: "http://127.0.0.1:53682/callback",
        accessToken: "at-1",
        refreshToken: "rt-1",
        expiresAt: 1_000
    )

    private func root() -> URL { FileManager.default.temporaryDirectory.appending(path: UUID().uuidString) }

    @Test func `a server's sign-in is saved, read back, and removed, keeping every other record`() throws {
        let root = root()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = CredentialFile(url: root.appending(path: "credentials.json"))
        try file.saveKey(StoredKey(key: "unrelated", obtainedAt: 1), for: "other")
        try file.saveMCP(Self.record)
        #expect(try file.loadMCP(server: "https://mcp.example.com/mcp") == Self.record)
        #expect(try file.loadMCP(server: "https://else.example/mcp") == nil)
        try file.removeMCP(server: "https://mcp.example.com/mcp")
        #expect(try file.loadMCP(server: "https://mcp.example.com/mcp") == nil)
        #expect(try file.loadKey(for: "other")?.key == "unrelated")
    }

    @Test func `with a secret store, the tokens are not in the file, and still read back`() throws {
        let root = root()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MemorySecretStore()
        let file = CredentialFile(url: root.appending(path: "credentials.json"), secrets: store)
        try file.saveMCP(Self.record)
        let text = try String(contentsOf: file.url, encoding: .utf8)
        #expect(!text.contains("at-1") && !text.contains("rt-1"), "the tokens are in the store")
        #expect(text.contains("client-1"), "the metadata stays in the file")
        #expect(try file.loadMCP(server: Self.record.server) == Self.record)
    }
}
