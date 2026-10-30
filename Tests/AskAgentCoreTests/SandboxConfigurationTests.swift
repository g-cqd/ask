import Foundation
import Testing

@testable import AskAgentCore

/// The `sandbox` section of the configuration: what it accepts, who may set what, and how the layers combine.
@Suite("The sandbox section lets the user adjust the default, and a project can only narrow it")
struct SandboxConfigurationTests {
    private func parse(_ text: String, project: Bool = false) throws(ConfigurationError) -> ConfigurationFile {
        try ConfigurationFile.parse(Array(text.utf8), path: "c.json", isProject: project)
    }

    @Test func `both lists are read, in JSON5, with the home shorthand`() throws {
        let file = try parse(
            """
            {
              // for the aws CLI
              sandbox: { readable: ['~/.aws'], hide: ["/Users/g/work/secrets", '~/clients'], },
            }
            """)
        #expect(
            file.sandbox == SandboxSection(allowRead: ["~/.aws"], denyRead: ["/Users/g/work/secrets", "~/clients"]))
        #expect(file.sets("sandbox") && !ConfigurationFile().sets("sandbox"))
    }

    @Test func `a relative path, an unknown key or a wrong type is refused, naming the key`() {
        #expect(
            throws: ConfigurationError.outOfRange(
                path: "c.json", key: "sandbox.hide",
                reason: "has \"secrets\": use an absolute path, or one starting with ~/")
        ) { try parse("{sandbox: {hide: ['secrets']}}") }
        #expect(
            throws: ConfigurationError.unknownKey(
                path: "c.json", key: "sandbox.allowExecute", known: ConfigurationFile.keys)
        ) {
            try parse("{sandbox: {allowExecute: ['/tmp']}}")
        }
        #expect(throws: ConfigurationError.self) { try parse("{sandbox: {readable: '~/.aws'}}") }
        #expect(throws: ConfigurationError.self) { try parse("{sandbox: ['~/.aws']}") }
    }

    @Test func `a project's file may narrow the sandbox but not widen it`() throws {
        let narrowing = try parse("{sandbox: {hide: ['~/clients']}}", project: true)
        #expect(narrowing.sandbox?.denyRead == ["~/clients"])
        #expect(
            throws: ConfigurationError.outOfRange(
                path: "c.json", key: "sandbox.readable",
                reason:
                    "can only be set in your own config file: a project that could widen the sandbox would defeat it")
        ) { try parse("{sandbox: {readable: ['~/.aws']}}", project: true) }
        #expect(try parse("{sandbox: {readable: ['~/.aws']}}").sandbox?.allowRead == ["~/.aws"])
    }

    @Test func `layers combine: what may be read is replaced, what is kept unreadable accumulates`() {
        let user = Configuration.defaults.applying(
            ConfigurationFile(sandbox: SandboxSection(allowRead: ["~/.aws"], denyRead: ["~/a"])), from: .file("/u"))
        let project = user.applying(
            ConfigurationFile(sandbox: SandboxSection(denyRead: ["~/b", "~/a"])), from: .file("/p"))
        #expect(project.sandbox.value == SandboxSection(allowRead: ["~/.aws"], denyRead: ["~/a", "~/b"]))
        #expect(project.sandbox.source == .file("/p"))
        let again = project.applying(
            ConfigurationFile(sandbox: SandboxSection(allowRead: ["~/.gnupg"])), from: .file("/u2"))
        #expect(again.sandbox.value.allowRead == ["~/.gnupg"] && again.sandbox.value.denyRead == ["~/a", "~/b"])
        #expect(Configuration.defaults.sandbox.value.isEmpty)
    }

    @Test func `a reload reports a change to the sandbox section`() {
        let before = Configuration.defaults
        let after = before.applying(
            ConfigurationFile(sandbox: SandboxSection(allowRead: ["~/.aws"])), from: .file("/u"))
        #expect(after.changes(from: before) == ["sandbox: \(before.sandbox.value) → readable [\"~/.aws\"] (/u)"])
    }

    @Test func `the home shorthand expands only at the start`() {
        #expect(SandboxSection.expand("~/.aws", home: "/Users/g") == "/Users/g/.aws")
        #expect(SandboxSection.expand("~", home: "/Users/g") == "/Users/g")
        #expect(SandboxSection.expand("/opt/~/x", home: "/Users/g") == "/opt/~/x")
        #expect(SandboxSection.expand("~other/x", home: "/Users/g") == "~other/x")
    }

    @Test func `a trusted project file that tries to widen the sandbox makes the load fail, naming the key`() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "ask-sbcfg-\(UUID().uuidString)")
        let project = root.appending(path: "project/.ask")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appending(path: "config"), withIntermediateDirectories: true)
        let text = "{sandbox: {allowRead: ['~/.aws']}}"
        try Data(text.utf8).write(to: project.appending(path: "config.json"))
        let loader = ConfigurationLoader(
            project: root.appending(path: "project").path, configDirectory: root.appending(path: "config").path,
            environment: [:])
        var trust = ProjectTrust()
        trust.trust(loader.projectPath, bytes: Array(text.utf8))
        try trust.save(to: loader.trustPath)
        #expect(throws: ConfigurationError.self) { try loader.load() }
    }
}
