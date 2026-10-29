import Foundation
import Testing

@testable import AskAI

/// `auto` never moves secrets out of the Keychain: an unsigned build (a test build, the quality gate's) run against the person's
/// configuration keeps using the Keychain once the file says its secrets are there.
@Suite("auto keeps secrets where they already are")
struct CredentialStorageAutoTests {
    @Test
    func `an unsigned build uses the Keychain when the file already keeps its secrets there, and the file otherwise`()
        throws
    {
        let directory = FileManager.default.temporaryDirectory.appending(path: "ask-auto-\(UUID().uuidString)/ask")
        let url = directory.appending(path: "credentials.json")
        let store = MemorySecretStore()
        try CredentialFile(url: url).saveKey(StoredKey(key: "inline", obtainedAt: 1), for: "a")
        #expect(CredentialFile.preferred(url: url, choice: .auto, stablySigned: false, keychain: store).secrets == nil)
        try CredentialFile(url: url, secrets: store).settleSecrets()
        #expect(CredentialFile.preferred(url: url, choice: .auto, stablySigned: false, keychain: store).secrets != nil)
        #expect(CredentialFile.preferred(url: url, choice: .file, stablySigned: true, keychain: store).secrets == nil)
        #expect(CredentialFile.preferred(url: url, choice: .auto, stablySigned: true, keychain: store).secrets != nil)
    }
}
