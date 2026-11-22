import AskAI
import Darwin
import Foundation
import Testing

@testable import AskAgentCore

/// An organisation's configuration (roadmap 0130, ADR-0168): `defaults.json` applies before the person's file, `requirements.json` after
/// every file, variable and flag, each key by its rule; a document anyone but its owner could write, or one that does not parse, stops
/// the load. Tests cannot make root's files, so the folder here is the test's own and the owner trusted is the one running it.
@Suite("An organisation's configuration", .serialized)
struct ManagedConfigurationTests {
    private let root = FileManager.default.temporaryDirectory.appending(path: "ask-managed-\(UUID().uuidString)").path

    private var managedFolder: String { root + "/managed" }

    private func write(_ path: String, _ text: String, mode: Int16 = 0o644) throws {
        let folder = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        try Data(text.utf8).write(to: URL(filePath: path))
        try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: path)
    }

    private func loader(owner: UInt32 = getuid()) -> ConfigurationLoader {
        ConfigurationLoader(
            project: root + "/project",
            configDirectory: root + "/config",
            environment: [:],
            managed: ManagedFiles(directory: managedFolder, owner: owner)
        )
    }

    @Test func `a requirement wins over your file and a flag; a default loses to your file`() throws {
        defer { try? FileManager.default.removeItem(atPath: root) }
        try write(managedFolder + "/requirements.json", #"{"model": "required-model"}"#)
        try write(managedFolder + "/defaults.json", #"{"thinking": "high", "maxTurns": 40}"#)
        try write(root + "/config/config.json", #"{"model": "mine", "thinking": "low"}"#)
        let loaded = try loader().load(model: "flagged")
        #expect(loaded.configuration.model.value == "required-model")
        #expect(loaded.configuration.model.source == .managed(managedFolder + "/requirements.json", required: true))
        #expect(loaded.configuration.thinking.value == .low, "your file is above the organisation's default")
        #expect(loaded.configuration.maxTurns.value == 40)
        #expect(loaded.configuration.maxTurns.source.description.hasSuffix("(your organisation's default)"))
        #expect(
            loaded.applied == [
                managedFolder + "/defaults.json", root + "/config/config.json", managedFolder + "/requirements.json"
            ]
        )
    }

    @Test func `a required scope narrows what a flag widened, and a protective list keeps your additions too`() throws {
        defer { try? FileManager.default.removeItem(atPath: root) }
        try write(
            managedFolder + "/requirements.json",
            #"{"sandbox": {"write": "workspace", "network": "provider"}, "environment": {"withhold": ["CORP_*"]}}"#
        )
        try write(
            root + "/config/config.json",
            #"{"environment": {"withhold": ["MINE"]}, "sandbox": {"network": "localhost"}}"#
        )
        let loaded = try loader().load(network: .any, write: .anywhere)
        let sandbox = loaded.configuration.sandbox.value
        #expect(
            sandbox.writeScope(workspace: "/w", home: "/h") == PathSetting.workspace.scope(workspace: "/w", home: "/h"),
            "--write anywhere cannot widen past the requirement"
        )
        #expect(sandbox.network == .provider, "--network any cannot widen past the requirement")
        #expect(loaded.configuration.environment.value.withhold == ["CORP_*", "MINE"])
    }

    @Test func `a stricter value from below still counts where the rule narrows`() throws {
        defer { try? FileManager.default.removeItem(atPath: root) }
        try write(managedFolder + "/requirements.json", #"{"sandbox": {"network": "provider"}}"#)
        try write(root + "/config/config.json", #"{"sandbox": {"network": "none"}}"#)
        #expect(try loader().load().configuration.sandbox.value.network == SandboxPolicy.Network.none)
    }

    @Test func `drop-ins apply after the main document, in name order`() throws {
        defer { try? FileManager.default.removeItem(atPath: root) }
        try write(managedFolder + "/requirements.json", #"{"model": "main"}"#)
        try write(managedFolder + "/requirements.d/20-second.json", #"{"model": "second"}"#)
        try write(managedFolder + "/requirements.d/10-first.json", #"{"model": "first", "maxTurns": 7}"#)
        let loaded = try loader().load()
        #expect(loaded.configuration.model.value == "second" && loaded.configuration.maxTurns.value == 7)
    }

    @Test func `no folder, no organisation: nothing changes`() throws {
        defer { try? FileManager.default.removeItem(atPath: root) }
        try write(root + "/config/config.json", #"{"model": "mine"}"#)
        let loaded = try loader().load()
        #expect(loaded.configuration.model.value == "mine" && loaded.applied == [root + "/config/config.json"])
    }

    @Test func `a document others may write, or someone else's, stops the load and says which`() throws {
        defer { try? FileManager.default.removeItem(atPath: root) }
        let path = managedFolder + "/requirements.json"
        try write(path, #"{"model": "required-model"}"#, mode: 0o666)
        #expect(throws: ConfigurationError.self) { try loader().load() }
        do { _ = try loader().load() } catch {
            guard case .untrusted(let named, _) = error else {
                Issue.record("\(error)")
                return
            }
            #expect(named == path)
        }
        try FileManager.default.setAttributes([.posixPermissions: Int16(0o644)], ofItemAtPath: path)
        #expect(throws: ConfigurationError.self) { try loader(owner: getuid() + 1).load() }
        #expect(try loader().load().configuration.model.value == "required-model")
    }

    @Test func `a link is judged by where it leads`() throws {
        defer { try? FileManager.default.removeItem(atPath: root) }
        let elsewhere = root + "/open/requirements.json"
        try write(elsewhere, #"{"model": "planted"}"#)
        try FileManager.default.setAttributes([.posixPermissions: Int16(0o777)], ofItemAtPath: root + "/open")
        try FileManager.default.createDirectory(atPath: managedFolder, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            atPath: managedFolder + "/requirements.json",
            withDestinationPath: elsewhere
        )
        #expect(throws: ConfigurationError.self) { try loader().load() }
    }

    @Test func `a document that does not parse stops the load, named`() throws {
        defer { try? FileManager.default.removeItem(atPath: root) }
        try write(managedFolder + "/defaults.d/10-team.json", #"{"model": "#)
        #expect(throws: ConfigurationError.self) { try loader().load() }
        try write(managedFolder + "/defaults.d/10-team.json", #"{"modle": "x"}"#)
        do { _ = try loader().load() } catch {
            #expect(error.description.hasPrefix(managedFolder + "/defaults.d/10-team.json"))
        }
    }

    @Test func `a connection's alias may change the organisation's default thinking, never its requirement`() throws {
        defer { try? FileManager.default.removeItem(atPath: root) }
        try write(managedFolder + "/defaults.json", #"{"thinking": "high"}"#)
        let suggested = try loader().load().configuration.applying(aliasThinking: .low, alias: "work/fast")
        #expect(suggested.thinking.value == .low)
        try write(managedFolder + "/requirements.json", #"{"thinking": "high"}"#)
        let required = try loader().load().configuration.applying(aliasThinking: .low, alias: "work/fast")
        #expect(required.thinking.value == .high)
    }

    @Test func `what a requirement sets is recorded key by key, and a key above counts`() throws {
        defer { try? FileManager.default.removeItem(atPath: root) }
        let path = managedFolder + "/requirements.json"
        try write(
            path,
            #"{"model": "m", "ui": {"tint": false}, "sandbox": {"network": "provider"}, "mcp": {"docs": {"url": "https://d.example/mcp"}}}"#
        )
        try write(managedFolder + "/defaults.json", #"{"thinking": "high", "ui": {"mouse": false}}"#)
        let configuration = try loader().load().configuration
        for key in ["model", "ui.tint", "sandbox.network", "mcp.docs", "mcp.docs.url"] {
            #expect(configuration.requirement(of: key) == path, "\(key)")
        }
        for key in ["thinking", "ui.mouse", "ui", "sandbox.write", "mcp.other"] {
            #expect(configuration.requirement(of: key) == nil, "\(key)")
        }
    }

    @Test func `a model chosen for one run does not replace a required one`() throws {
        defer { try? FileManager.default.removeItem(atPath: root) }
        try write(managedFolder + "/requirements.json", #"{"provider": "work"}"#)
        let required = try loader().load().configuration
        let chosen = required.applying(selectedProvider: "elsewhere", model: "other", command: "/model")
        #expect(chosen.provider.value == "work" && chosen.model == required.model)
        let free = Configuration.defaults.applying(selectedProvider: "elsewhere", model: "other", command: "/model")
        #expect(free.provider.value == "elsewhere" && free.model.value == "other")
    }
}
