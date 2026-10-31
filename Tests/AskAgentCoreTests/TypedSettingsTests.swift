internal import Testing

@testable import AskAgentCore

/// Settings take plain JSON types (roadmap 0118, owner's decisions of 2026-10-31): `null` where a value means none at all, and `compactAt`
/// a number, tokens or a share of the window. The words of before are still read, so an old file keeps working.
@Suite("Settings take plain JSON types: null for none, a number for compactAt")
struct TypedSettingsTests {
    private func parse(_ text: String) throws -> ConfigurationFile {
        try ConfigurationFile.parse(Array(text.utf8), path: "c.json")
    }

    @Test func `maxTurns null is no limit, and the word of before still reads`() throws {
        #expect(try parse(#"{"maxTurns": null}"#).maxTurns == Configuration.noTurnLimit)
        #expect(try parse(#"{"maxTurns": "none"}"#).maxTurns == Configuration.noTurnLimit)
        #expect(Configuration.describeTurns(Configuration.noTurnLimit) == "null")
    }

    @Test(arguments: [
        (#"{"compactAt": 0.95}"#, CompactionThreshold.share(95)), (#"{"compactAt": 0.5}"#, .share(50)),
        (#"{"compactAt": 1}"#, .share(100)), (#"{"compactAt": 100000}"#, .tokens(100_000)),
        (#"{"compactAt": 0}"#, .tokens(0)),
        (#"{"compactAt": "75%"}"#, .share(75))
    ])
    func `compactAt is a share up to 1, tokens above it, or 0 for only when full`(
        text: String, expected: CompactionThreshold
    ) throws {
        #expect(try parse(text).compactAt == expected)
    }

    @Test(arguments: [
        #"{"compactAt": 0.955}"#, #"{"compactAt": 1.5}"#, #"{"compactAt": -0.5}"#, #"{"compactAt": "0.95"}"#
    ])
    func `a share finer than a whole percent, a fraction of a token, or a number as a string is refused`(text: String) {
        #expect(throws: ConfigurationError.self) { try parse(text) }
    }

    @Test func `the flag and the variable take the same numbers`() {
        #expect(CompactionThreshold(parsing: "0.95") == .share(95))
        #expect(CompactionThreshold(parsing: "100000") == .tokens(100_000))
        var problems: [String] = []
        let set = Configuration.defaults.applying(environment: ["ASK_COMPACT_AT": "0.6"], problems: &problems)
        #expect(set.compactAt.value == .share(60) && problems.isEmpty)
    }

    @Test func `a share is said as the number a file takes`() {
        #expect(CompactionThreshold.share(75).description == "0.75")
        #expect(CompactionThreshold.share(100).description == "1")
        #expect(CompactionThreshold.tokens(150_000).description == "150000")
    }
}
