internal import Foundation
internal import Testing

@testable import AskAI

struct ConnectionAliasStoreTests {
    private func withRegistry(_ body: (ConnectionRegistry) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "ask-alias-store-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try body(ConnectionRegistry(directory: root))
    }

    @Test func `aliases live in the connection's own folder, and a rename keeps them`() throws {
        try withRegistry { registry in
            let record = try registry.register(name: "work", provider: .codex)
            let file = registry.aliases(for: record)
            #expect(
                file.url.deletingLastPathComponent()
                    == registry.credentials(for: record).url.deletingLastPathComponent())
            try file.set("fast", to: "gpt-6-luna")
            try registry.rename(record, to: "employer")
            let renamed = try #require(registry.list().records.first)
            #expect(registry.aliases(for: renamed).url == file.url)
            let value3 = try registry.aliases(for: renamed).load().aliases["fast"]?.model
            #expect(value3 == "gpt-6-luna")
        }
    }

    @Test func `two connections have separate aliases, and a removed name starts again with none`() throws {
        try withRegistry { registry in
            let work = try registry.register(name: "work", provider: .codex)
            let home = try registry.register(name: "home", provider: .codex)
            try registry.aliases(for: work).set("fast", to: "gpt-6-luna")
            let value4 = try registry.aliases(for: home).load()
            #expect(value4 == .empty)
            try registry.remove(work)
            let again = try registry.register(name: "work", provider: .codex)
            #expect(again.id != work.id)
            #expect(
                try registry.aliases(for: again).load() == .empty,
                "a new registration never inherits an old one's aliases")
        }
    }
}
