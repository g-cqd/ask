internal import Foundation
internal import Testing

@testable import AskAI

struct ModelAliasFileTests {
    private func withFile(lockWait: Duration = .seconds(5), _ body: (ModelAliasFile) async throws -> Void) async throws
    {
        let root = FileManager.default.temporaryDirectory.appending(path: "ask-aliasfile-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try await body(ModelAliasFile(url: root.appending(path: "connection/aliases.json"), lockWait: lockWait))
    }

    @Test func `reading a missing file gives no aliases and creates nothing`() async throws {
        try await withFile { file in
            let value1 = try file.load()
            #expect(value1 == .empty)
            #expect(!FileManager.default.fileExists(atPath: file.url.deletingLastPathComponent().path))
        }
    }

    @Test func `a change is saved whole, owner-only, and read back`() async throws {
        try await withFile { file in
            try file.set("fast", to: "gpt-6-luna", contextWindow: 9000)
            try file.setDefault("fast")
            let loaded = try file.load()
            #expect(loaded.aliases["fast"] == ModelAlias(model: "gpt-6-luna", contextWindow: 9000))
            #expect(loaded.defaultModel == "fast")
            let mode = try FileManager.default.attributesOfItem(atPath: file.url.path)[.posixPermissions] as? NSNumber
            #expect(mode?.intValue == 0o600)
            let directory = file.url.deletingLastPathComponent().path
            #expect(
                (try FileManager.default.attributesOfItem(atPath: directory)[.posixPermissions] as? NSNumber)?.intValue
                    == 0o700)
        }
    }

    @Test func `a change that throws saves nothing and creates nothing`() async throws {
        try await withFile { file in
            #expect(throws: ModelAliasError.invalidName) { try file.set("bad name", to: "m") }
            #expect(!FileManager.default.fileExists(atPath: file.url.path))
            try file.set("ok", to: "m")
            let before = try Data(contentsOf: file.url)
            #expect(throws: ModelAliasError.notFound("missing")) { try file.remove("missing") }
            #expect(try Data(contentsOf: file.url) == before)
        }
    }

    @Test func `a damaged file is reported and never overwritten`() async throws {
        try await withFile { file in
            try FileManager.default.createDirectory(
                at: file.url.deletingLastPathComponent(), withIntermediateDirectories: true)
            for bytes in [Data("{broken".utf8), Data("[]".utf8), Data(repeating: 120, count: (1 << 20) + 1)] {
                try bytes.write(to: file.url)
                #expect(throws: ModelAliasError.damaged(path: file.url.path)) { try file.load() }
                #expect(throws: ModelAliasError.damaged(path: file.url.path)) {
                    try file.set("a", to: "m")
                }
                #expect(try Data(contentsOf: file.url) == bytes)
            }
        }
    }

    @Test(arguments: [
        #"{"version":1,"aliases":{"Fast":{"model":"m"}}}"#, #"{"version":1,"aliases":{"fAst":{"model":"m"}}}"#,
        #"{"version":1,"aliases":{"bad name":{"model":"m"}}}"#,
        #"{"version":1,"aliases":{"a":{"model":"bad model"}}}"#,
        #"{"version":1,"aliases":{"a":{"model":"m","contextWindow":0}}}"#,
        #"{"version":1,"aliases":{"a":{"model":"m","maxOutputTokens":-5}}}"#,
        #"{"version":1,"aliases":{},"default":"bad default"}"#, #"{"version":0,"aliases":{}}"#
    ])
    func `a hand-edited file that ask would refuse to write is damaged, and is not trusted`(_ text: String) async throws
    {
        try await withFile { file in
            try FileManager.default.createDirectory(
                at: file.url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: file.url)
            #expect(throws: ModelAliasError.damaged(path: file.url.path)) { try file.load() }
            #expect(try Data(contentsOf: file.url) == Data(text.utf8))
        }
    }

    @Test func `a file from a newer ask is refused, not rewritten`() async throws {
        try await withFile { file in
            try FileManager.default.createDirectory(
                at: file.url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let bytes = Data(#"{"version":3,"aliases":{},"extra":{"keep":true}}"#.utf8)
            try bytes.write(to: file.url)
            #expect(throws: ModelAliasError.newerFormat(path: file.url.path)) { try file.load() }
            #expect(throws: ModelAliasError.newerFormat(path: file.url.path)) {
                try file.set("a", to: "m")
            }
            #expect(try Data(contentsOf: file.url) == bytes)
        }
    }

    @Test func `concurrent changes to different aliases all survive`() async throws {
        try await withFile { file in
            try await withThrowingTaskGroup(of: Void.self) { group in
                for index in 0 ..< 8 {
                    group.addTask { try file.set("alias-\(index)", to: "model-\(index)") }
                }
                try await group.waitForAll()
            }
            let value2 = try file.load().aliases.count
            #expect(value2 == 8)
        }
    }

    @Test func `a change that cannot get the lock says so and writes nothing`() async throws {
        try await withFile(lockWait: .milliseconds(150)) { file in
            try file.set("first", to: "m")
            let before = try Data(contentsOf: file.url)
            let held = try await CredentialLock.acquire(beside: file.url, wait: .seconds(1), name: "aliases")
            defer { held.release() }
            let lock = CredentialLock.path(beside: file.url, name: "aliases")
            #expect(throws: ModelAliasError.locked(path: lock)) { try file.set("second", to: "m") }
            #expect(try Data(contentsOf: file.url) == before)
        }
    }

    @Test func `reading takes no lock and writes nothing`() async throws {
        try await withFile { file in
            try file.set("fast", to: "m")
            let directory = file.url.deletingLastPathComponent().path
            let names = try FileManager.default.contentsOfDirectory(atPath: directory).sorted()
            let bytes = try Data(contentsOf: file.url)
            _ = try file.load()
            #expect(try FileManager.default.contentsOfDirectory(atPath: directory).sorted() == names)
            #expect(try Data(contentsOf: file.url) == bytes)
        }
    }
}
