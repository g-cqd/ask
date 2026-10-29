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
}
