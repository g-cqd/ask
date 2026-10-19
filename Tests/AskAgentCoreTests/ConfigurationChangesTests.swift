import Testing

@testable import AskAgentCore

/// What a reload says changed: one line per setting, old value, new value, and where the new one came from.
@Suite("A reload says what changed, and from where")
struct ConfigurationChangesTests {
    @Test func `nothing changed says nothing`() {
        #expect(Configuration.defaults.changes(from: .defaults).isEmpty)
    }

    @Test func `each changed setting is a line with both values and the new source`() {
        let before = Configuration.defaults.applying(ConfigurationFile(maxTurns: 40), from: .file("/u/config.json"))
        let after = before.applying(
            ConfigurationFile(model: "haiku", maxTurns: 7, compactAt: 0), from: .file("/p/.ask/config.json"))
        #expect(
            after.changes(from: before) == [
                "model: default → \"haiku\" (/p/.ask/config.json)",
                "maxTurns: 40 → 7 (/p/.ask/config.json)",
                "compactAt: 150000 → 0 (/p/.ask/config.json)"
            ])
    }

    @Test func `a value that stays the same but comes from elsewhere is a change of source`() {
        let user = Configuration.defaults.applying(ConfigurationFile(maxTurns: 40), from: .file("/u/config.json"))
        var problems: [String] = []
        let env = user.applying(environment: ["ASK_MAX_TURNS": "40"], problems: &problems)
        #expect(env.changes(from: user) == ["maxTurns: 40 → 40 ($ASK_MAX_TURNS)"])
    }

    @Test func `flags are the top layer, over the environment`() {
        var problems: [String] = []
        let env = Configuration.defaults.applying(environment: ["ASK_MAX_TURNS": "9"], problems: &problems)
        let flagged = env.applying(model: nil, provider: nil, maxTurns: 2, compactAt: nil)
        #expect(flagged.maxTurns == .init(value: 2, source: .flag("max-turns")))
    }
}
