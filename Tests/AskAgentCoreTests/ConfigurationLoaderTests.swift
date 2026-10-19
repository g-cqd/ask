import Foundation
import Testing

@testable import AskAgentCore

/// The layers, in order, and the rule that a project's file counts only for the bytes the user trusted.
@Suite("Configuration layers apply in order, and a project file counts only when trusted")
struct ConfigurationLoaderTests {
    private let root = FileManager.default.temporaryDirectory.appending(path: "ask-config-\(UUID().uuidString)")
    private var configDirectory: String { root.path + "/config" }
    private var project: String { root.path + "/project" }

    private func write(_ path: String, _ text: String) throws {
        try FileManager.default.createDirectory(
            atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try Data(text.utf8).write(to: URL(filePath: path))
    }

    private func loader(environment: [String: String] = [:]) -> ConfigurationLoader {
        ConfigurationLoader(project: project, configDirectory: configDirectory, environment: environment)
    }

    private func trustProject() throws {
        var trust = ProjectTrust()
        trust.trust(loader().projectPath, bytes: [UInt8](try Data(contentsOf: URL(filePath: loader().projectPath))))
        try trust.save(to: loader().trustPath)
    }

    @Test func `with no files there are only defaults`() throws {
        let result = try loader().load()
        #expect(result.configuration == .defaults)
        #expect(result.applied.isEmpty && result.notices.isEmpty)
    }

    @Test func `each layer replaces what it sets and leaves the rest, and says where each value came from`() throws {
        try write(loader().userPath, "{model: 'user-model', maxTurns: 10, compactAt: 5000}")
        try write(loader().projectPath, "{maxTurns: 20}")
        try trustProject()
        let result = try loader(environment: ["ASK_MAX_TURNS": "30", "ASK_PROVIDER": "local"])
            .load(compactAt: 7000)
        let configuration = result.configuration
        #expect(configuration.model == .init(value: "user-model", source: .file(loader().userPath)))
        #expect(configuration.maxTurns == .init(value: 30, source: .environment("ASK_MAX_TURNS")))
        #expect(configuration.provider == .init(value: "local", source: .environment("ASK_PROVIDER")))
        #expect(configuration.compactAt == .init(value: 7000, source: .flag("compact-at")))
        #expect(result.applied == [loader().userPath, loader().projectPath])
    }

    @Test func `a flag beats the environment for the same key, and the environment beats a trusted project file`()
        throws
    {
        try write(loader().projectPath, "{maxTurns: 20, compactAt: 111}")
        try trustProject()
        let result = try loader(environment: ["ASK_MAX_TURNS": "30", "ASK_COMPACT_AT": "222"]).load(maxTurns: 2)
        #expect(result.configuration.maxTurns == .init(value: 2, source: .flag("max-turns")))
        #expect(result.configuration.compactAt == .init(value: 222, source: .environment("ASK_COMPACT_AT")))
    }

    @Test func `a project file that was never trusted is ignored, with a notice that says how to use it`() throws {
        try write(loader().projectPath, "{maxTurns: 3}")
        let result = try loader().load()
        #expect(result.configuration.maxTurns.value == 100)
        #expect(result.notices == ["\(loader().projectPath) is ignored: run `ask trust` here to use it."])
    }

    @Test func `a trusted project file that changed afterwards is ignored until trusted again`() throws {
        try write(loader().projectPath, "{maxTurns: 3}")
        try trustProject()
        #expect(try loader().load().configuration.maxTurns.value == 3)
        try write(loader().projectPath, "{maxTurns: 3000}")
        let result = try loader().load()
        #expect(result.configuration.maxTurns.value == 100)
        #expect(result.notices.first?.contains("changed since you trusted it") == true)
    }

    @Test func `a broken user file or trusted project file refuses the load, and an untrusted one is not even parsed`()
        throws
    {
        try write(loader().userPath, "{maxTurns: ]")
        #expect(throws: ConfigurationError.self) { try loader().load() }
        try FileManager.default.removeItem(atPath: loader().userPath)
        try write(loader().projectPath, "{maxTurns: ]")
        #expect(try loader().load().notices.count == 1, "untrusted: ignored without reading its contents")
        var trust = ProjectTrust()
        trust.trust(loader().projectPath, bytes: Array("{maxTurns: ]".utf8))
        try trust.save(to: loader().trustPath)
        #expect(throws: ConfigurationError.self) { try loader().load() }
    }

    @Test func `an environment value that is not a number in range is ignored and named`() throws {
        let result = try loader(environment: ["ASK_MAX_TURNS": "many", "ASK_COMPACT_AT": "-5"]).load()
        #expect(result.configuration.maxTurns.value == 100 && result.configuration.compactAt.source == .defaults)
        #expect(result.notices.count == 2)
        #expect(result.notices[0].contains("$ASK_MAX_TURNS is \"many\""))
    }

    @Test func `a file that exists but cannot be read is an error naming the reason, never treated as absent`() throws {
        for (path, text) in [(loader().userPath, "{}"), (loader().projectPath, "{}")] {
            try write(path, text)
            try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: path)
            defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path) }
            #expect(throws: ConfigurationError.unreadable(path: path, errno: EACCES)) { try loader().load() }
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
            try FileManager.default.removeItem(atPath: path)
        }
    }

    @Test func `a file far larger than any configuration is refused unread`() throws {
        try write(loader().userPath, "{" + String(repeating: " ", count: 2 << 20) + "}")
        #expect(throws: ConfigurationError.self) { try loader().load() }
    }

    @Test func `a corrupted trust store is an error, not an empty one`() throws {
        try write(loader().projectPath, "{maxTurns: 3}")
        try write(loader().trustPath, "not json at all")
        #expect(throws: ConfigurationError.self) { try loader().load() }
    }

    @Test func `the trust store is owner-only, and trust can be withdrawn`() throws {
        var trust = ProjectTrust()
        trust.trust("/p/.ask/config.json", bytes: Array("x".utf8))
        try trust.save(to: loader().trustPath)
        let mode = try FileManager.default.attributesOfItem(atPath: loader().trustPath)[.posixPermissions] as? Int
        #expect(mode == 0o600)
        var again = try ProjectTrust.load(loader().trustPath)
        #expect(again.standing(of: "/p/.ask/config.json", bytes: Array("x".utf8)) == .trusted)
        #expect(again.standing(of: "/p/.ask/config.json", bytes: Array("y".utf8)) == .changed)
        #expect(again.standing(of: "/q/.ask/config.json", bytes: Array("x".utf8)) == .unknown)
        #expect(again.untrust("/p/.ask/config.json") && !again.untrust("/p/.ask/config.json"))
        #expect(again.paths.isEmpty)
    }
}
