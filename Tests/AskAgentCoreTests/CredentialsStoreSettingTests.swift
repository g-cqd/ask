import AskAI
import Testing

@testable import AskAgentCore

/// `credentials` (roadmap 0110): where keys and tokens are kept, `auto` by default, chosen only in the person's own file.
struct CredentialsStoreSettingTests {
    @Test func `credentials is read from the person's file, defaults to auto, and refuses what it does not know`()
        throws
    {
        #expect(Configuration.defaults.credentials.value == .auto)
        let file = try ConfigurationFile.parse(Array(#"{"credentials": "file"}"#.utf8), path: "c.json")
        #expect(file.credentials == .file)
        let configured = Configuration.defaults.applying(file, from: .file("/u/config.json"))
        #expect(configured.changes(from: .defaults) == ["credentials: auto → file (/u/config.json)"])
        #expect(throws: (any Error).self) {
            try ConfigurationFile.parse(Array(#"{"credentials": "vault"}"#.utf8), path: "c.json")
        }
    }

    @Test func `a project's file cannot choose where the person's keys are kept`() {
        #expect(throws: (any Error).self) {
            try ConfigurationFile.parse(Array(#"{"credentials": "file"}"#.utf8), path: "p.json", isProject: true)
        }
    }

    @Test func `auto is the Keychain for a build with a stable signature, and the file for an ad-hoc one`() {
        #expect(CredentialStorage.auto.usesKeychain(stablySigned: true))
        #expect(!CredentialStorage.auto.usesKeychain(stablySigned: false))
        #expect(CredentialStorage.keychain.usesKeychain(stablySigned: false))
        #expect(!CredentialStorage.file.usesKeychain(stablySigned: true))
    }
}
