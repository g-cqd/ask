import Foundation
import Testing

@testable import AskAI

/// The Keychain store against a throwaway keychain file, never the login keychain: items round-trip, update in place, are removed,
/// and one service's items are not another's.
@Suite("The Keychain store keeps items in the keychain it is given", .serialized)
struct KeychainSecretStoreTests {
    private let path: String

    init() throws {
        path = FileManager.default.temporaryDirectory.appending(path: "ask-kc-\(UUID().uuidString).keychain-db").path
        for arguments in [
            ["create-keychain", "-p", "test", path], ["set-keychain-settings", path],
            ["unlock-keychain", "-p", "test", path]
        ] {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
            process.arguments = arguments
            try process.run()
            process.waitUntilExit()
            try #require(process.terminationStatus == 0, "security \(arguments[0])")
        }
    }

    private func discard() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["delete-keychain", path]
        try? process.run()
        process.waitUntilExit()
    }

    @Test func `an item is stored, read back, updated in place and removed`() throws {
        defer { discard() }
        let store = try KeychainSecretStore(service: "ask-test", keychainPath: path)
        #expect(try store.secrets(for: "a") == nil)
        try store.store(["token": "one"], for: "a")
        #expect(try store.secrets(for: "a") == ["token": "one"])
        try store.store(["token": "two", "other": "x"], for: "a")
        #expect(try store.secrets(for: "a") == ["token": "two", "other": "x"])
        try store.remove(account: "a")
        #expect(try store.secrets(for: "a") == nil)
        try store.remove(account: "a")
    }

    @Test func `two services keep their items apart`() throws {
        defer { discard() }
        let first = try KeychainSecretStore(service: "ask-test-1", keychainPath: path)
        let second = try KeychainSecretStore(service: "ask-test-2", keychainPath: path)
        try first.store(["k": "1"], for: "same")
        #expect(try second.secrets(for: "same") == nil)
    }
}
