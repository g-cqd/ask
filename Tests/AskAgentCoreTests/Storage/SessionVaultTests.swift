import AskAI
import Foundation
import Testing

@testable import AskAgentCore

/// ask's side of the keys (ADR-0138): `keys.json` and the first-start answer in the state directory, the keychain when remembered.
@Suite
struct SessionVaultTests {
    private let vault: SessionVault

    init() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "ask-vault-\(UUID().uuidString)").path
        vault = SessionVault(stateRoot: directory, derivation: SessionKeysTests.quick)
    }

    @Test
    func `keys made with a password open with it or the recovery code, and keys.json is private`() throws {
        #expect(!vault.hasKeys)
        let made = try vault.create(password: "a long passphrase")
        #expect(vault.hasKeys)
        #expect(try vault.unlock(password: "a long passphrase").userKey == made.keyring.userKey)
        #expect(try vault.unlock(recoveryCode: made.recoveryCode).userKey == made.keyring.userKey)
        #expect(throws: SessionKeyError.wrongPassword) { _ = try vault.unlock(password: "another") }
        let attributes = try FileManager.default.attributesOfItem(atPath: vault.keysPath)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        #expect(throws: SessionVaultError.keysExist) { _ = try vault.create(password: "again") }
    }

    @Test
    func `changing the password keeps every session readable`() throws {
        let made = try vault.create(password: "first")
        try vault.changePassword(made.keyring, to: "second")
        #expect(try vault.unlock(password: "second").userKey == made.keyring.userKey)
        #expect(throws: SessionKeyError.wrongPassword) { _ = try vault.unlock(password: "first") }
    }

    @Test
    func `the first-start answer is kept, and absent until given`() throws {
        #expect(vault.choice() == nil)
        try vault.record(SessionEncryptionChoice(encrypt: true, remember: false))
        #expect(vault.choice() == SessionEncryptionChoice(encrypt: true, remember: false))
    }

    @Test
    func `a remembered keyring comes back from the keychain, and not once forgotten`() throws {
        let store = RememberedSessionKeyTests.Kept()
        let made = try vault.create(password: "pw")
        #expect(vault.remembered(in: store) == nil)
        try vault.remember(made.keyring, in: store)
        #expect(vault.remembered(in: store)?.userKey == made.keyring.userKey)
        try vault.forget(in: store)
        #expect(vault.remembered(in: store) == nil)
    }

    @Test
    func `the settings and the first-start answer decide together, the settings first`() {
        let asked = SessionEncryptionChoice(encrypt: true, remember: false)
        #expect(SessionEncryptionPolicy(setting: nil, password: nil, choice: nil).needsFirstStartQuestion)
        let fromChoice = SessionEncryptionPolicy(setting: nil, password: nil, choice: asked)
        #expect(fromChoice.mode == .on && fromChoice.remember == false && !fromChoice.needsFirstStartQuestion)
        let fromSettings = SessionEncryptionPolicy(setting: .off, password: .remember, choice: asked)
        #expect(fromSettings.mode == .off && fromSettings.remember)
        let declined = SessionEncryptionPolicy(
            setting: nil,
            password: nil,
            choice: SessionEncryptionChoice(encrypt: false, remember: true)
        )
        #expect(declined.mode == .off)
    }
}
