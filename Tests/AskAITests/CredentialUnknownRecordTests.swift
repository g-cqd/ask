internal import Foundation
internal import Testing

@testable import AskAI

/// A writer owns its credential records, not every record a newer ask might put beside them.
struct CredentialUnknownRecordTests {
    private func withFile(_ body: (CredentialFile) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "ask-future-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let file = CredentialFile(url: root.appending(path: "ask/credentials.json"))
        try file.saveKey(StoredKey(key: "seed", obtainedAt: 1), for: "seed")
        try body(file)
    }

    @Test func `unknown object records survive every kind of save without changing their number lexemes`() throws {
        try withFile { file in
            let unknown = #"{ "huge": 18446744073709551615, "fraction": 0.1234567890123456789012345, "exp": 1e-100 }"#
            try Data((#"{"future": "# + unknown + "}").utf8).write(to: file.url)
            let codex = CodexCredentials(accessToken: "a", refreshToken: "r", expiresAt: 1, accountID: "account")
            try file.saveCodex(codex)
            #expect(try String(contentsOf: file.url, encoding: .utf8).contains(unknown))
            try file.saveClaude(
                ClaudeCredentials(
                    accessToken: "ca", refreshToken: "cr", expiresAt: 1, refreshExpiresAt: nil,
                    accountEmail: nil, organizationName: nil, scopes: "scope"))
            #expect(try String(contentsOf: file.url, encoding: .utf8).contains(unknown))
            try file.saveKey(StoredKey(key: "k", obtainedAt: 2), for: "another")
            #expect(try String(contentsOf: file.url, encoding: .utf8).contains(unknown))
            #expect(try file.loadCodex() == codex)
        }
    }

    @Test func `unknown arrays strings booleans and null survive removal of a known record`() throws {
        try withFile { file in
            let fragments = [#"[ 1, {"id":18446744073709551615}, [false,null] ]"#, #""escaped\ntext""#, "true", "null"]
            for fragment in fragments {
                try Data((#"{"future": "# + fragment + #", "keys":{"seed":{"key":"old","obtainedAt":1}}}"#).utf8)
                    .write(to: file.url)
                try file.removeKey(for: "seed")
                #expect(try String(contentsOf: file.url, encoding: .utf8).contains(fragment), "\(fragment)")
                #expect(try file.loadKey(for: "seed") == nil)
            }
        }
    }

    @Test func `an unknown record is not resurrected as a known credential when signing out`() throws {
        try withFile { file in
            try Data(
                #"{"future":{"opaque":true},"codex":{"accessToken":"a","refreshToken":"r","expiresAt":1,"accountID":"account"}}"#
                    .utf8
            )
            .write(to: file.url)
            try file.removeCodex()
            let text = try String(contentsOf: file.url, encoding: .utf8)
            #expect(text.contains(#""future":{"opaque":true}"#))
            #expect(!text.contains("accessToken"))
            #expect(try file.loadCodex() == nil)
        }
    }

    @Test func `reading a legacy file with unknown records leaves its bytes unchanged`() throws {
        try withFile { file in
            let bytes = Data(#"{ "future": [123, null], "keys": {} }"#.utf8)
            try bytes.write(to: file.url)
            _ = try file.loadCodex()
            _ = try file.loadClaude()
            _ = try file.loadKeys()
            #expect(try Data(contentsOf: file.url) == bytes)
        }
    }

    @Test func `a newer registration schema is refused rather than normalized by an older writer`() throws {
        try withFile { file in
            var registration = ConnectionRecord(name: "future", provider: .codex)
            registration.schemaVersion = 2
            var stored = StoredCredentials()
            stored.connection = registration
            let bytes = Data(try stored.encoded())
            try bytes.write(to: file.url)
            #expect(throws: CredentialFileError.newerFormat(path: file.url.path)) { try file.loadCodex() }
            #expect(throws: CredentialFileError.newerFormat(path: file.url.path)) {
                try file.saveKey(StoredKey(key: "not-saved", obtainedAt: 1), for: "other")
            }
            #expect(try Data(contentsOf: file.url) == bytes)
        }
    }

    @Test func `whole-store logout intentionally removes unknown records too`() throws {
        try withFile { file in
            try Data(#"{"future":{"secret":"opaque"}}"#.utf8).write(to: file.url)
            try file.remove()
            #expect(!FileManager.default.fileExists(atPath: file.url.path))
        }
    }
}
