internal import AskAI
internal import Testing

@testable import AskAgentCore

/// An alias level is more specific than a configuration file, and less than this run's own say.
struct AliasThinkingPrecedenceTests {
    @Test func `it replaces the built-in default and says where it came from`() {
        let next = Configuration.defaults.applying(aliasThinking: .xhigh, alias: "work/deep")
        #expect(next.thinking.value == .xhigh)
        #expect(next.thinking.source == .alias("work/deep"))
        #expect(next.thinking.source.description == "alias work/deep")
    }

    @Test(arguments: [ThinkingLevel.high, .providerDefault])
    func `it replaces a level from a configuration file, including an explicit default`(_ file: ThinkingLevel) {
        let configured = Configuration.defaults.applying(ConfigurationFile(thinking: file), from: .file("user"))
        let next = configured.applying(aliasThinking: .low, alias: "work/fast")
        #expect(next.thinking.value == .low)
        #expect(next.thinking.source == .alias("work/fast"))
    }

    @Test func `the environment and a flag still win, because they are this run's say`() {
        var notices: [String] = []
        let environment = Configuration.defaults.applying(environment: ["ASK_THINKING": "medium"], problems: &notices)
        #expect(environment.applying(aliasThinking: .xhigh, alias: "work/deep") == environment)
        let flagged = Configuration.defaults.applying(
            model: nil, provider: nil, maxTurns: nil, compactAt: nil, thinking: .off)
        #expect(flagged.applying(aliasThinking: .xhigh, alias: "work/deep") == flagged)
    }

    @Test func `reload reports a level that came from an alias`() {
        let next = Configuration.defaults.applying(aliasThinking: .xhigh, alias: "work/deep")
        #expect(next.changes(from: .defaults) == ["thinking: default → xhigh (alias work/deep)"])
    }
}
