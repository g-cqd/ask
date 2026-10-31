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
            ConfigurationFile(model: "haiku", maxTurns: 7, compactAt: .tokens(0)), from: .file("/p/.ask/config.json"))
        #expect(
            after.changes(from: before) == [
                "model: default → \"haiku\" (/p/.ask/config.json)",
                "maxTurns: 40 → 7 (/p/.ask/config.json)",
                "compactAt: 0.75 → 0 (/p/.ask/config.json)"
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

    @Test func `maxTurns "none" removes the limit from a file or the environment, and shows as null`() throws {
        let file = try ConfigurationFile.parse(Array(#"{"maxTurns": "none"}"#.utf8), path: "c.json")
        #expect(file.maxTurns == Configuration.noTurnLimit)
        let unlimited = Configuration.defaults.applying(file, from: .file("/u/config.json"))
        #expect(unlimited.changes(from: .defaults) == ["maxTurns: 100 → null (/u/config.json)"])
        var problems: [String] = []
        let env = Configuration.defaults.applying(environment: ["ASK_MAX_TURNS": "none"], problems: &problems)
        #expect(env.maxTurns.value == Configuration.noTurnLimit && problems.isEmpty)
        #expect(throws: (any Error).self) {
            try ConfigurationFile.parse(Array(#"{"maxTurns": "lots"}"#.utf8), path: "c.json")
        }
        #expect(throws: (any Error).self) {
            try ConfigurationFile.parse(Array(#"{"maxTurns": 0}"#.utf8), path: "c.json")
        }
        #expect(
            Configuration.describeTurns(Configuration.noTurnLimit) == "null" && Configuration.describeTurns(30) == "30")
    }

    @Test func `unset, the turn limit is 100 in the sandbox and none outside it; set anywhere, it wins either way`()
        throws
    {
        #expect(Configuration.defaults.turnLimit(sandboxed: true) == 100)
        #expect(Configuration.defaults.turnLimit(sandboxed: false) == Configuration.noTurnLimit)
        let forty = Configuration.defaults.applying(ConfigurationFile(maxTurns: 40), from: .file("/u/config.json"))
        #expect(forty.turnLimit(sandboxed: true) == 40 && forty.turnLimit(sandboxed: false) == 40)
        let none = Configuration.defaults.applying(
            try ConfigurationFile.parse(Array(#"{"maxTurns": "none"}"#.utf8), path: "c.json"), from: .file("c.json"))
        #expect(none.turnLimit(sandboxed: true) == Configuration.noTurnLimit)
        var problems: [String] = []
        let hundred = Configuration.defaults.applying(environment: ["ASK_MAX_TURNS": "100"], problems: &problems)
        #expect(hundred.turnLimit(sandboxed: false) == 100, "100 written out is a choice, not the default")
    }
}
