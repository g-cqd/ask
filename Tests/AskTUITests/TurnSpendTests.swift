import Foundation
import Testing

@testable import AskTUI

/// The last turn's cost on the status line (roadmap 0239): three lengths, a figure that is not known left out, and gone when the next
/// turn begins.
@Suite("The last turn's cost on the status line")
struct TurnSpendTests {
    private let spend = TurnSpend(requests: 4, toolCalls: 6, tokens: "↑45k ↓3.1k", seconds: 72, toolSeconds: 30)

    @Test func `three lengths, longest first, as a clock`() {
        #expect(
            spend.forms(localized: false) == [
                "last turn 4 requests, 6 tools · ↑45k ↓3.1k · 1:12, tools 0:30", "turn ↑45k ↓3.1k 1:12", "turn 1:12"
            ]
        )
    }

    @Test func `one request and no tool, and figures not known, are left out rather than said as zero`() {
        let one = TurnSpend(requests: 1, toolCalls: 0, tokens: nil, seconds: nil, toolSeconds: nil)
        #expect(one.forms(localized: false) == ["last turn 1 request", "turn"])
        let timed = TurnSpend(requests: 1, toolCalls: 0, tokens: "↑1.2k ↓80", seconds: 5, toolSeconds: 0)
        #expect(
            timed.forms(localized: false) == [
                "last turn 1 request · ↑1.2k ↓80 · 0:05", "turn ↑1.2k ↓80 0:05", "turn 0:05"
            ]
        )
    }

    @Test func `a done task's line says the same, with hours past an hour`() {
        let long = TurnSpend(requests: 1, toolCalls: 2, tokens: nil, seconds: 3_725, toolSeconds: 3)
        #expect(long.summary(localized: false) == "1 request, 2 tools · 1:02:05, tools 0:03")
    }

    @Test func `durations in the locale's words when the screen says them so`() {
        #expect(spend.forms(localized: true).last == "turn " + DurationText.localized(72))
    }

    @Test func `the status line shows it after the session's tokens until it is cleared`() {
        var controller = ScreenController(label: "m", options: .legacy)
        _ = controller.apply(.status("↑1.2M ↓34k"))
        _ = controller.apply(.turnSpent(spend))
        let texts = ScreenComposer.segments(for: controller.state, input: "").map { $0.forms[0] }
        let session = texts.firstIndex(of: "↑1.2M ↓34k")
        let turn = texts.firstIndex { $0.hasPrefix("last turn") }
        #expect(session != nil && turn != nil && session! < turn!)
        _ = controller.apply(.turnSpent(nil))
        #expect(
            !ScreenComposer.segments(for: controller.state, input: "").contains { $0.forms[0].hasPrefix("last turn") }
        )
    }
}
