import Foundation
import Testing

@testable import AskAI

@Suite("Copilot refresh and logout preserve account transactions")
struct CopilotStorageTests {
    private func stored(_ root: URL) throws -> CredentialFile {
        let file = CredentialFile(url: root.appending(path: "config/credentials.json"))
        try file.saveKey(StoredKey(key: "unrelated", obtainedAt: 1), for: "other")
        try file.saveCopilot(
            CopilotCredentials(
                githubToken: "grant", accessToken: "expired", expiresAt: 0,
                apiURL: CopilotProtocol.defaultAPI, machineID: "machine", deviceID: "device"))
        return file
    }
    private static let envelope = #"{"token":"renewed","expires_at":1,"refresh_in":600}"#

    @Test func `refresh is persisted and reused while unrelated credentials survive logout`() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = try stored(root)
        let transport = CopilotTestTransport { _ in CopilotTestTransport.reply(Self.envelope) }
        let access = CopilotAccess(file: file, transport: transport)
        let fresh = try await access.credentials(now: 1000)
        #expect(fresh.accessToken == "renewed" && fresh.expiresAt == 1600)
        #expect(fresh.machineID == "machine" && fresh.githubToken == "grant")
        #expect(try await access.credentials(now: 1001) == fresh)
        #expect(transport.requests.count == 1)
        #expect(try file.signedInAccounts(environment: [:]).contains { $0.provider == CopilotProtocol.name })
        #expect(try file.signOut(target: CopilotProtocol.name))
        #expect(try file.loadCopilot() == nil)
        #expect(try file.loadKey(for: "other")?.key == "unrelated")
        let mode = try FileManager.default.attributesOfItem(atPath: file.url.path)[.posixPermissions] as? NSNumber
        #expect(mode?.intValue == 0o600)
    }

    @Test func `sign out during refresh cannot resurrect a credential`() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = try stored(root)
        let transport = CopilotTestTransport { _ in
            try file.signOut(target: CopilotProtocol.name)
            return CopilotTestTransport.reply(Self.envelope)
        }
        await #expect(throws: (any Error).self) {
            _ = try await CopilotAccess(file: file, transport: transport).credentials(now: 1000)
        }
        #expect(try file.loadCopilot() == nil)
    }
}
