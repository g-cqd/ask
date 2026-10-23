internal import AemiJSON
internal import Foundation
internal import Testing

@testable import AskAI

/// An alias can carry a thinking level, so `work/deep` means a model and how hard it thinks.
struct AliasThinkingTests {
    private func withFile(_ body: (ModelAliasFile) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "ask-alias-thinking-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try body(ModelAliasFile(url: root.appending(path: "connection/aliases.json")))
    }

    private func version(_ file: ModelAliasFile) throws -> Int? {
        try AemiJSON.parse(Array(try Data(contentsOf: file.url))).root["version"].int
    }

    @Test(arguments: ThinkingLevel.allCases)
    func `a level is stored, read back and chosen with the alias`(_ level: ThinkingLevel) throws {
        try withFile { file in
            try file.set("deep", to: "gpt-6-sol", thinking: level)
            let loaded = try file.load()
            #expect(loaded.aliases["deep"]?.thinking == level)
            let choice = try loaded.choice(requested: "deep", catalog: [])
            #expect(choice?.thinking == level)
            #expect(choice?.model == "gpt-6-sol")
        }
    }

    @Test func `a file with no level stays in the format older builds read, byte for byte`() throws {
        try withFile { file in
            try file.set("fast", to: "gpt-6-luna", contextWindow: 9000)
            #expect(try version(file) == 1)
            let text = String(decoding: try Data(contentsOf: file.url), as: UTF8.self)
            #expect(!text.contains("thinking"))
        }
    }

    @Test func `a level moves the file to a version older builds refuse, rather than silently drop`() throws {
        try withFile { file in
            try file.set("fast", to: "gpt-6-luna")
            try file.set("deep", to: "gpt-6-sol", thinking: .xhigh)
            #expect(try version(file) == 2)
            try file.set("deep", to: "gpt-6-sol")
            #expect(try version(file) == 1, "with no level left, older builds may read it again")
        }
    }

    @Test func `a model typed directly, not an alias, carries no level`() throws {
        var aliases = ModelAliases()
        try aliases.set("deep", to: "gpt-6-sol", thinking: .high)
        let direct = try aliases.choice(requested: "gpt-6-sol", catalog: [])
        #expect(direct?.thinking == nil)
    }

    @Test(arguments: [#""ultra""#, #""HIGH""#, "true", "3", #""""#])
    func `a hand-edited unknown level makes the file damaged, not quietly ignored`(_ level: String) throws {
        try withFile { file in
            try FileManager.default.createDirectory(
                at: file.url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(#"{"version":2,"aliases":{"deep":{"model":"gpt-6-sol","thinking":\#(level)}}}"#.utf8)
                .write(to: file.url)
            #expect(throws: ModelAliasError.damaged(path: file.url.path)) { try file.load() }
        }
    }

    @Test func `a level in a file still marked version 1 is read rather than lost`() throws {
        try withFile { file in
            try FileManager.default.createDirectory(
                at: file.url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(#"{"version":1,"aliases":{"deep":{"model":"gpt-6-sol","thinking":"low"}}}"#.utf8)
                .write(to: file.url)
            #expect(try file.load().aliases["deep"]?.thinking == .low)
        }
    }

    @Test func `a version this build does not know is still refused`() throws {
        try withFile { file in
            try FileManager.default.createDirectory(
                at: file.url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(#"{"version":3,"aliases":{}}"#.utf8).write(to: file.url)
            #expect(throws: ModelAliasError.newerFormat(path: file.url.path)) { try file.load() }
        }
    }

    @Test func `the resolved model carries the alias level, and only a named connection's`() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "ask-alias-thinking-reg-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let work = try ConnectionRegistry(directory: root).register(name: "work", provider: .codex)
        var aliases = ModelAliases()
        try aliases.set("deep", to: "gpt-6-sol", thinking: .xhigh)
        let resolved = try ProviderSettings.none.resolve(
            provider: "work", model: "deep", environment: [:], connection: work, aliases: aliases)
        #expect(resolved.thinking == .xhigh)
        let plain = try ProviderSettings.none.resolve(
            provider: "codex", model: "gpt-6-sol", environment: [:], aliases: aliases)
        #expect(plain.thinking == nil)
    }
}
