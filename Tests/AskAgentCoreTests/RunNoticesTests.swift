import AskAI
import Testing

@testable import AskAgentCore

/// What a run says to a person (roadmap 0028): a compaction's notice and a retry's, the same words in the screen and in `ask -p`.
@Suite("A compaction and a retry are said in words a person reads the same way either way")
struct RunNoticesTests {
    @Test func `a compaction says what replaced what, and that nothing was lost`() {
        let summary = String(repeating: "s", count: 137)
        let notice = RunNotices.compaction(for: .compacted(summary: summary, usage: TokenUsage()))
        #expect(
            notice
                == "Compacted the conversation: earlier messages are now a 137-character summary. The session file keeps them all."
        )
    }

    @Test func `a compaction that failed says why and that the run goes on`() {
        #expect(
            RunNotices.compaction(for: .compactionFailed("the summarising request failed"))
                == "Could not compact (the summarising request failed); continuing with the whole conversation.")
    }

    @Test func `anything else is not a compaction`() {
        #expect(RunNotices.compaction(for: .finished(nil)) == nil)
        #expect(RunNotices.compaction(for: .model(.notice("hi"))) == nil)
    }

    @Test func `a retry says why, how long, and which attempt`() {
        #expect(
            RunNotices.retry(attempt: 2, of: 4, delay: .seconds(3), reason: "rate limited")
                == "rate limited; retrying in 3 s (attempt 2 of 4).")
        #expect(
            RunNotices.retry(attempt: 1, of: 3, delay: .milliseconds(500), reason: "overloaded")
                == "overloaded; retrying in 0.5 s (attempt 1 of 3).")
    }

    @Test func `a wait of a fraction says the fraction`() {
        #expect(RunNotices.retry(attempt: 1, of: 2, delay: .milliseconds(1_250), reason: "x").contains("1.25 s"))
    }
}
