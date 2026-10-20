internal import Foundation
internal import Testing

@testable import AskAI

struct ConnectionRegistryTests {
    private static let codex = CodexCredentials(
        accessToken: "access", refreshToken: "refresh", expiresAt: 1000, accountID: "account-a")
    private func withRegistry(_ body: (ConnectionRegistry) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "ask-connections-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try body(ConnectionRegistry(directory: root.appending(path: "connections")))
    }

    @Test func `listing an unused registry creates nothing`() throws {
        try withRegistry { registry in
            let listing = try registry.list()
            #expect(listing.records.isEmpty && listing.notices.isEmpty)
            #expect(!FileManager.default.fileExists(atPath: registry.directory.path))
        }
    }

    @Test func `two accounts of the same provider retain different stable stores`() throws {
        try withRegistry { registry in
            let a = try registry.register(name: "Personal", provider: .codex)
            let b = try registry.register(name: "work", provider: .codex)
            #expect(a.name == "personal")
            #expect(a.id != b.id)
            try registry.saveCodex(Self.codex, for: a)
            #expect(try registry.credentials(for: a).loadCodex() == Self.codex)
            #expect(try registry.credentials(for: b).loadCodex() == nil)
            #expect(try registry.list().records.map(\.name) == ["personal", "work"])
            #expect(registry.credentials(for: a).url != registry.credentials(for: b).url)
        }
    }

    @Test(arguments: ["", "../work", "a/b", "-work", "a\nwork", String(repeating: "a", count: 65)])
    func `invalid names never become paths`(_ name: String) throws {
        try withRegistry { registry in
            #expect(throws: ConnectionError.invalidName) { try registry.register(name: name, provider: .codex) }
            #expect(!FileManager.default.fileExists(atPath: registry.directory.path))
        }
    }

    @Test(arguments: ["codex", "CLAUDE", "anthropic", "groq", "local"])
    func `builtins presets and configured names cannot be shadowed`(_ name: String) throws {
        try withRegistry { registry in
            #expect(throws: ConnectionError.nameInUse(name.lowercased())) {
                try registry.register(name: name, provider: .codex, reserved: ["LOCAL"])
            }
        }
    }

    @Test func `registration is idempotent only for the same provider`() throws {
        try withRegistry { registry in
            let record = try registry.register(name: "work", provider: .codex)
            #expect(try registry.register(name: "WORK", provider: .codex) == record)
            #expect(throws: ConnectionError.nameInUse("work")) {
                try registry.register(name: "work", provider: .anthropic)
            }
        }
    }

    @Test func `rename retains credentials and identity but refuses another destination's name`() throws {
        try withRegistry { registry in
            let record = try registry.register(name: "work", provider: .codex)
            try registry.saveCodex(Self.codex, for: record)
            let installed = try #require(registry.list().records.first)
            try registry.rename(installed, to: "Employer")
            let renamed = try #require(registry.list().records.first)
            #expect(renamed.name == "employer" && renamed.id == installed.id)
            #expect(renamed.authorizationID == installed.authorizationID)
            #expect(try registry.credentials(for: renamed).loadCodex() == Self.codex)
            #expect(throws: ConnectionError.nameInUse("groq")) { try registry.rename(renamed, to: "groq") }
        }
    }

    @Test func `signout retains the registration and defeats a pending login`() throws {
        try withRegistry { registry in
            let record = try registry.register(name: "work", provider: .codex)
            try registry.saveCodex(Self.codex, for: record)
            let beforeLogout = try #require(registry.list().records.first)
            try registry.signOut(beforeLogout)
            let after = try #require(registry.list().records.first)
            #expect(after.id == beforeLogout.id && after.authorizationID != beforeLogout.authorizationID)
            #expect(try registry.credentials(for: after).loadCodex() == nil)
            #expect(throws: ConnectionError.changed("work")) { try registry.saveCodex(Self.codex, for: beforeLogout) }
            #expect(try registry.credentials(for: after).loadCodex() == nil)
        }
    }

    @Test func `replacing a remote account needs consent and rotates the binding identity`() throws {
        try withRegistry { registry in
            let record = try registry.register(name: "work", provider: .codex)
            try registry.saveCodex(Self.codex, for: record)
            let old = try #require(registry.list().records.first)
            let other = CodexCredentials(
                accessToken: "other", refreshToken: "other-refresh", expiresAt: 1000, accountID: "account-b")
            #expect(throws: ConnectionError.replacementRequired("work")) { try registry.saveCodex(other, for: old) }
            #expect(try registry.credentials(for: old).loadCodex() == Self.codex)
            try registry.saveCodex(other, for: old, replaceAccount: true)
            let current = try #require(registry.list().records.first)
            #expect(current.id == old.id && current.authorizationID != old.authorizationID)
            #expect(try registry.credentials(for: current).loadCodex() == other)
        }
    }

    @Test func `remove frees the name but never reuses an old session's stable id`() throws {
        try withRegistry { registry in
            let old = try registry.register(name: "work", provider: .codex)
            try registry.saveCodex(Self.codex, for: old)
            try registry.remove(old)
            #expect(try registry.list().records.isEmpty)
            #expect(throws: ConnectionError.changed("work")) { try registry.saveCodex(Self.codex, for: old) }
            let new = try registry.register(name: "work", provider: .codex)
            #expect(new.id != old.id)
            #expect(try registry.credentials(for: new).loadCodex() == nil)
        }
    }

    @Test func `a busy registration lock gives an actionable error without allocating another identity`() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "ask-registry-lock-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let registry = ConnectionRegistry(directory: root, lockWait: .zero)
        _ = try registry.register(name: "existing", provider: .codex)
        let held = try await CredentialLock.acquire(beside: root.appending(path: ".registry"), wait: .zero)
        defer { held.release() }
        #expect(throws: CredentialFileError.locked(path: root.appending(path: ".registry.lock").path)) {
            try registry.register(name: "other", provider: .codex)
        }
        #expect(try registry.list().records.map(\.name) == ["existing"])
    }

    @Test func `signing out clears opaque credentials too but leaves a cache beside the profile`() throws {
        try withRegistry { registry in
            let record = try registry.register(name: "work", provider: .codex)
            let file = registry.credentials(for: record)
            try file.transact(creating: false) { stored in
                stored.codex = Self.codex
                return ((), true)
            }
            var text = try String(contentsOf: file.url, encoding: .utf8)
            text.removeLast()
            text += #", "future_secret": {"opaque":"not-retained"}}"#
            try Data(text.utf8).write(to: file.url)
            let cache = file.url.deletingLastPathComponent().appending(path: "models-codex.json")
            try Data("cache remains".utf8).write(to: cache)
            try registry.signOut(record)
            let after = try String(contentsOf: file.url, encoding: .utf8)
            #expect(!after.contains("future_secret") && !after.contains("not-retained"))
            #expect(try String(contentsOf: cache, encoding: .utf8) == "cache remains")
            #expect(try registry.list().records.map(\.id) == [record.id])
        }
    }

    @Test func `one damaged profile is reported without hiding another`() throws {
        try withRegistry { registry in
            let good = try registry.register(name: "personal", provider: .codex)
            let bad = try registry.register(name: "work", provider: .codex)
            let path = registry.credentials(for: bad).url
            try Data("{broken".utf8).write(to: path)
            let bytes = try Data(contentsOf: path)
            let listing = try registry.list()
            #expect(listing.records.map(\.id) == [good.id])
            #expect(listing.notices.count == 1)
            #expect(try Data(contentsOf: path) == bytes)
        }
    }
}
