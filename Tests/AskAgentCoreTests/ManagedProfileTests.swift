import AskAI
import Darwin
import Foundation
import Testing

@testable import AskAgentCore

/// A configuration profile for the domain `studio.aemi.ask` (ADR-0168, phase 3): its `requirements` and `defaults` dictionaries read as
/// `config.json` files, the machine's then the user's, after the organisation's files; macOS's own keys ignored, any other refused.
@Suite("A configuration profile", .serialized)
struct ManagedProfileTests {
    private let root = FileManager.default.temporaryDirectory.appending(path: "ask-profile-\(UUID().uuidString)").path
    private var preferences: String { root + "/Managed Preferences" }
    private var machine: String { preferences + "/studio.aemi.ask.plist" }
    private var person: String { preferences + "/me/studio.aemi.ask.plist" }

    private func write(_ plist: [String: Any], to path: String, mode: Int16 = 0o644) throws {
        try FileManager.default.createDirectory(
            atPath: (path as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true
        )
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: URL(filePath: path))
        try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: path)
    }

    private func loader() -> ConfigurationLoader {
        ConfigurationLoader(
            project: root + "/project",
            configDirectory: root + "/config",
            environment: [:],
            managed: ManagedFiles(
                directory: root + "/files",
                owner: getuid(),
                profile: ManagedProfile(directory: preferences, user: "me", owner: getuid())
            )
        )
    }

    @Test func `the machine's profile, then the person's, with macOS's own keys ignored`() throws {
        defer { try? FileManager.default.removeItem(atPath: root) }
        try write(
            [
                "PayloadUUID": "7BE22222", "_isRestricted": true,
                "requirements": ["model": "machine-model", "maxTurns": 20], "defaults": ["thinking": "high"]
            ],
            to: machine
        )
        try write(["requirements": ["model": "person-model"]], to: person)
        try FileManager.default.createDirectory(atPath: root + "/config", withIntermediateDirectories: true)
        try Data(#"{"model": "mine", "thinking": "low"}"#.utf8).write(to: URL(filePath: root + "/config/config.json"))
        let configuration = try loader().load().configuration
        #expect(configuration.model.value == "person-model")
        #expect(configuration.model.source == .managed(person + ": requirements", required: true))
        #expect(configuration.maxTurns.value == 20 && configuration.thinking.value == .low)
        #expect(configuration.requirement(of: "maxTurns") == machine + ": requirements")
    }

    @Test func `a profile's values read as the same keys written in JSON`() throws {
        defer { try? FileManager.default.removeItem(atPath: root) }
        try write(
            [
                "requirements": [
                    "compactAt": 0.5, "codemode": false,
                    "ui": ["tint": false, "scrollLines": 5], "environment": ["withhold": ["CORP_*", "X"]],
                    "sandbox": ["write": ["~/work", "/tmp"], "network": "provider"]
                ]
            ],
            to: machine
        )
        let required = try loader().load().configuration
        let json = try ConfigurationFile.parse(
            Array(
                #"{"compactAt": 0.5, "codemode": false, "ui": {"tint": false, "scrollLines": 5}, "environment": {"withhold": ["CORP_*", "X"]}, "sandbox": {"write": ["~/work", "/tmp"], "network": "provider"}}"#
                    .utf8
            ),
            path: "json"
        )
        let expected = Configuration.defaults.applying(json, from: .managed("json", required: true))
        #expect(
            required.compactAt.value == expected.compactAt.value && required.codemode.value == expected.codemode.value
        )
        #expect(required.ui.value == expected.ui.value && required.environment.value == expected.environment.value)
        #expect(required.sandbox.value == expected.sandbox.value)
    }

    @Test func `the files come first, the profile after`() throws {
        defer { try? FileManager.default.removeItem(atPath: root) }
        try FileManager.default.createDirectory(atPath: root + "/files", withIntermediateDirectories: true)
        try Data(#"{"model": "from-file"}"#.utf8).write(to: URL(filePath: root + "/files/requirements.json"))
        try write(["requirements": ["model": "from-profile"]], to: machine)
        #expect(try loader().load().configuration.model.value == "from-profile")
    }

    @Test func `a misspelt kind, a date, a bad key or a profile others may write stops the load`() throws {
        defer { try? FileManager.default.removeItem(atPath: root) }
        try write(["requirments": ["model": "m"]], to: machine)
        #expect(throws: ConfigurationError.self) { try loader().load() }
        try write(["requirements": ["model": Date()]], to: machine)
        #expect(throws: ConfigurationError.self) { try loader().load() }
        try write(["requirements": ["modle": "m"]], to: machine)
        do { _ = try loader().load() } catch {
            #expect(error.description.hasPrefix(machine + ": requirements"), "\(error)")
        }
        try write(["requirements": ["model": "m"]], to: machine, mode: 0o666)
        #expect(throws: ConfigurationError.self) { try loader().load() }
        try write(["requirements": ["model": "m"]], to: machine)
        #expect(try loader().load().configuration.model.value == "m")
    }
}
