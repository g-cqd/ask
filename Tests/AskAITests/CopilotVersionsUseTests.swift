import Foundation
import Testing

@testable import AskAI

/// Every Copilot request names the versions read: the token exchange, the catalogue and a chat; a cache file that holds anything but plain
/// versions is not believed.
@Suite("Every Copilot request names the versions read, and a tampered cache is not believed")
struct CopilotVersionsUseTests {
    private func transport() -> CopilotTestTransport {
        VSCodeBuildServer.transport { request in
            request.url.host == "api.github.com"
                ? CopilotTestTransport.reply(#"{"token":"renewed","expires_at":1,"refresh_in":600}"#)
                : CopilotTestTransport.reply(#"{"data":[]}"#)
        }
    }

    private func file(_ root: URL, expiresAt: Double) throws -> CredentialFile {
        let file = CredentialFile(url: root.appending(path: "config/credentials.json"))
        try file.saveCopilot(
            CopilotCredentials(
                githubToken: "grant",
                accessToken: "short",
                expiresAt: expiresAt,
                apiURL: CopilotProtocol.defaultAPI,
                machineID: "machine",
                deviceID: "device"
            )
        )
        return file
    }

    private func value(_ name: String, _ request: HTTPRequest?) -> String? {
        request?.headers.first { $0.name == name }?.value
    }

    @Test func `the token exchange names Copilot Chat's version`() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let transport = transport()
        _ = try await CopilotAccess(file: try file(root, expiresAt: 0), transport: transport).credentials(now: 1_000)
        let exchange = transport.requests.first { $0.url.host == "api.github.com" }
        #expect(value("user-agent", exchange) == "GitHubCopilotChat/0.80.1")
    }

    @Test func `the catalogue request names both versions`() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let transport = transport()
        let now = Date().timeIntervalSince1970
        _ = try await CopilotCatalog(file: try file(root, expiresAt: now + 3_600), transport: transport)
            .models(now: now, refresh: true)
        let models = transport.requests.first { $0.url.path == "/models" }
        #expect(value("editor-version", models) == "vscode/1.150.2")
        #expect(value("editor-plugin-version", models) == "copilot-chat/0.80.1")
        #expect(value("user-agent", models) == "GitHubCopilotChat/0.80.1")
    }

    @Test func `a cache holding more than a plain version is read again`() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = root.appending(path: "copilot-vscode-version.json")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data(#"{"version":{"vscode":"1.1\r\nx: y","chat":"0.1"},"at":1000}"#.utf8).write(to: cache)
        let transport = transport()
        let version = await CopilotVersions(cache: cache, transport: transport).current(now: 1_001)
        #expect(version == CopilotClientVersion(vscode: "1.150.2", chat: "0.80.1"))
        #expect(transport.requests.count == 5)
    }
}
