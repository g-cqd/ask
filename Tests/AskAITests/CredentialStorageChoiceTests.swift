import Foundation
import Testing

@testable import AskAI

/// Files are made with the process's choice of store, so every credential file follows the person's setting.
@Suite("Credential files follow the chosen store", .serialized)
struct CredentialStorageChoiceTests {
    @Test func `the preferred file uses the chosen store, and no store for the file mode`() {
        let url = FileManager.default.temporaryDirectory.appending(path: "c.json")
        CredentialStorage.choose(.file)
        #expect(CredentialFile.preferred(url: url).secrets == nil)
        CredentialStorage.choose(.keychain)
        #expect(CredentialFile.preferred(url: url).secrets is KeychainSecretStore)
        CredentialStorage.choose(.file)
    }

    /// A named connection's credentials follow the setting as ask's own file does: built without a store, they stayed in the file
    /// under `keychain` while the record said every file moves (found on the first signed build). The store is given, not the
    /// process's choice changed: other suites reach the registry in parallel, and must never meet the person's keychain.
    @Test func `a named connection's file uses the chosen store too`() {
        let registry = ConnectionRegistry(
            directory: FileManager.default.temporaryDirectory.appending(path: "connections"))
        let record = ConnectionRecord(name: "codex-2", provider: .codex)
        let store = MemorySecretStore()
        let kept = registry.credentials(for: record, choice: .keychain, stablySigned: false, keychain: store)
        #expect(kept.secrets as? MemorySecretStore === store)
        #expect(registry.credentials(for: record, choice: .file, stablySigned: true, keychain: store).secrets == nil)
        #expect(registry.credentials(for: record, choice: .auto, stablySigned: true, keychain: store).secrets != nil)
    }
}
