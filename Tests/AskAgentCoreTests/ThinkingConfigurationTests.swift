internal import AskAI
internal import Foundation
internal import Testing

@testable import AskAgentCore

struct ThinkingConfigurationTests {
    private func parse(_ text: String) throws -> ConfigurationFile {
        try ConfigurationFile.parse(Array(text.utf8), path: "/fixture/config.json")
    }

    @Test(arguments: ThinkingLevel.allCases)
    func `every thinking spelling is parsed and is a set key, including the explicit reset`(_ level: ThinkingLevel)
        throws
    {
        let file = try parse("{thinking: '\(level.rawValue)'}")
        #expect(file.thinking == level)
        #expect(file.sets("thinking"))
        #expect(ConfigurationFile.keys.contains("thinking"))
    }

    @Test(arguments: ["true", "null", "1", "[]", "{}", "'ultra'", "'HIGH'", "''"])
    func `a malformed or unsupported file level refuses that file`(_ value: String) {
        #expect(throws: ConfigurationError.self) { try parse("{thinking: \(value)}") }
    }

    @Test func `the invalid spelling diagnostic names the thinking choices`() {
        #expect(
            throws: ConfigurationError.outOfRange(
                path: "/fixture/config.json", key: "thinking",
                reason: "is \"ultra\": use \(SettingCatalog.either(ThinkingLevel.allCases.map(\.rawValue)))")
        ) {
            try parse("{thinking: 'ultra'}")
        }
    }

    @Test func `an absent key keeps defaults and an explicit default resets a lower layer`() throws {
        let defaults = Configuration.defaults
        #expect(defaults.thinking.value == .providerDefault && defaults.thinking.source == .defaults)
        let user = defaults.applying(ConfigurationFile(thinking: .high), from: .file("user"))
        #expect(user.thinking.value == .high && user.thinking.source == .file("user"))
        let absent = user.applying(try parse("{}"), from: .file("project"))
        #expect(absent.thinking == user.thinking)
        let reset = user.applying(try parse("{thinking: 'default'}"), from: .file("project"))
        #expect(reset.thinking.value == .providerDefault && reset.thinking.source == .file("project"))
    }

    @Test func `environment beats files, flags beat environment and default is not mistaken for absence`() {
        var notices: [String] = []
        let file = Configuration.defaults.applying(ConfigurationFile(thinking: .high), from: .file("user"))
        let environment = file.applying(environment: ["ASK_THINKING": "low"], problems: &notices)
        #expect(environment.thinking.value == .low && environment.thinking.source == .environment("ASK_THINKING"))
        let flag = environment.applying(
            model: nil, provider: nil, maxTurns: nil, compactAt: nil, thinking: .providerDefault)
        #expect(flag.thinking.value == .providerDefault && flag.thinking.source == .flag("thinking"))
        #expect(notices.isEmpty)
    }

    @Test func `an invalid nonempty thinking environment is named and ignored but an empty one is unset`() {
        var notices: [String] = []
        let base = Configuration.defaults.applying(ConfigurationFile(thinking: .high), from: .file("user"))
        let bad = base.applying(environment: ["ASK_THINKING": "fixture-bad-value"], problems: &notices)
        #expect(bad.thinking == base.thinking)
        #expect(notices.count == 1 && notices.first?.contains("ASK_THINKING") == true)
        notices.removeAll()
        let empty = base.applying(environment: ["ASK_THINKING": ""], problems: &notices)
        #expect(empty.thinking == base.thinking && notices.isEmpty)
    }

    @Test func `reload reports the level and its source even when only the source changed`() {
        let high = Configuration.defaults.applying(ConfigurationFile(thinking: .high), from: .file("user"))
        #expect(high.changes(from: .defaults).contains { $0.contains("thinking: default → high (user)") })
        let flagged = high.applying(model: nil, provider: nil, maxTurns: nil, compactAt: nil, thinking: .high)
        #expect(flagged.changes(from: high).contains { $0.contains("thinking") && $0.contains("--thinking") })
    }

    @Test func `a loader reload reads the new level and preserves a reset flag`() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "ask-thinking-config-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let loader = ConfigurationLoader(project: root.path, configDirectory: root.path, environment: [:])
        let path = URL(filePath: loader.userPath)
        try Data("{thinking: 'high'}".utf8).write(to: path)
        let first = try loader.load()
        #expect(first.configuration.thinking.value == .high)
        try Data("{thinking: 'low'}".utf8).write(to: path)
        let second = try loader.load()
        #expect(second.configuration.thinking.value == .low)
        #expect(second.configuration.changes(from: first.configuration).contains { $0.contains("thinking") })
        let reset = try loader.load(thinking: .providerDefault)
        #expect(
            reset.configuration.thinking.value == .providerDefault
                && reset.configuration.thinking.source == .flag("thinking"))
    }
}
