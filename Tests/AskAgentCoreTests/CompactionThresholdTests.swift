internal import Testing

@testable import AskAgentCore

/// `compactAt` is a share of the model's window or a number of tokens (roadmap 0104).
@Suite("The compaction threshold is a share of the window or a number of tokens")
struct CompactionThresholdTests {
    @Test(arguments: [
        ("75%", CompactionThreshold.share(75)), (" 100 % ", .share(100)), ("1%", .share(1)),
        ("150000", .tokens(150_000)),
        ("0", .tokens(0))
    ])
    func `a share or a token count parses`(text: String, expected: CompactionThreshold) {
        #expect(CompactionThreshold(parsing: text) == expected)
    }

    @Test(arguments: ["0%", "101%", "-1", "75", "%", "abc", "1.5", ""])
    func `anything else is refused`(text: String) {
        if text == "75" {
            #expect(CompactionThreshold(parsing: text) == .tokens(75))
        } else {
            #expect(CompactionThreshold(parsing: text) == nil)
        }
    }

    @Test func `a share is that part of the window, and falls back to the token default with no window`() {
        #expect(CompactionThreshold.share(75).tokens(window: 200_000) == 150_000)
        #expect(CompactionThreshold.share(75).tokens(window: 1_000_000) == 750_000)
        #expect(CompactionThreshold.share(75).tokens(window: nil) == AgentSettings.defaultCompactAtTokens)
        #expect(CompactionThreshold.tokens(0).tokens(window: 200_000) == nil)
        #expect(CompactionThreshold.tokens(9_000).tokens(window: 200_000) == 9_000)
    }

    @Test func `the default is three quarters of the window`() {
        #expect(Configuration.defaults.compactAt.value == .share(75))
    }

    @Test func `a file takes a share as a string and tokens as a number`() throws {
        #expect(
            try ConfigurationFile.parse(Array(#"{"compactAt": "60%"}"#.utf8), path: "c.json").compactAt == .share(60))
        #expect(
            try ConfigurationFile.parse(Array(#"{"compactAt": 90000}"#.utf8), path: "c.json").compactAt
                == .tokens(90_000))
        for bad in [#"{"compactAt": "150%"}"#, #"{"compactAt": "90000"}"#, #"{"compactAt": -1}"#] {
            #expect(throws: ConfigurationError.self) { try ConfigurationFile.parse(Array(bad.utf8), path: "c.json") }
        }
    }

    @Test func `ASK_COMPACT_AT takes a share, and a bad value is named and ignored`() {
        var problems: [String] = []
        let shared = Configuration.defaults.applying(environment: ["ASK_COMPACT_AT": "50%"], problems: &problems)
        #expect(shared.compactAt.value == .share(50) && problems.isEmpty)
        let bad = Configuration.defaults.applying(environment: ["ASK_COMPACT_AT": "half"], problems: &problems)
        #expect(bad.compactAt.value == .standard && problems.count == 1)
    }

    @Test func `a window the server shows later is compacted at the same share of it`() {
        var settings = AgentSettings(
            model: "m", maximumTokens: 1_024, systemPrompt: [], maximumTurns: 1, compactAtTokens: 150_000)
        settings.compactAtShare = 50
        #expect(AgentLoop.budget(for: settings, window: 100_000).compactAtTokens == 50_000)
        #expect(AgentLoop.budget(for: settings, window: nil).compactAtTokens == 150_000)
        settings.compactAtShare = nil
        // 150,000 tokens do not fit a 100,000 window: the threshold is narrowed to fit it.
        let narrowed = AgentLoop.budget(for: settings, window: 100_000).compactAtTokens
        #expect(narrowed.map { $0 < 100_000 } == true)
    }
}
