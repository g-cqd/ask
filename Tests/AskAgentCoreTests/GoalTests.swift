import AskAI
import Synchronization
import Testing

@testable import AskAgentCore

/// `/goal` (roadmap 0227): the judge's verdicts, and the hook that goes on, ends or stops at a bound.
@Suite("A goal is judged when a run would end")
struct GoalTests {
    @Test func `verdicts read from the reply's first words, anything else is not yet`() {
        #expect(GoalVerdict.parse("MET: all 12 tests pass") == .met("all 12 tests pass"))
        #expect(GoalVerdict.parse("  **NOT YET**: run swift test") == .notYet("run swift test"))
        #expect(GoalVerdict.parse("not yet - lint fails") == .notYet("lint fails"))
        #expect(GoalVerdict.parse("Impossible: the API was removed") == .impossible("the API was removed"))
        guard case .notYet(let reason) = GoalVerdict.parse("Probably done?") else {
            Issue.record("not yet")
            return
        }
        #expect(reason.contains("unclear"))
    }

    private func response() -> AssembledResponse {
        AssembledResponse(
            id: "r",
            model: "m",
            blocks: [.text("done")],
            stopReason: .endTurn,
            usage: TokenUsage(),
            unrecognized: []
        )
    }

    private final class Notices: Sendable {
        private let kept = Mutex<[String]>([])
        func add(_ text: String) { kept.withLock { $0.append(text) } }
        var all: [String] { kept.withLock { $0 } }
    }

    private func hook(_ state: GoalState, replies: [String?], goOn: Bool = false) -> (GoalHook, Notices) {
        let notices = Notices()
        let queue = Mutex(replies)
        let hook = GoalHook(
            state: state,
            judge: { _ in queue.withLock { $0.isEmpty ? nil : $0.removeFirst() } },
            recent: { "ran swift test" },
            atBound: { _ in goOn },
            notice: { notices.add($0) }
        )
        return (hook, notices)
    }

    @Test func `no goal, no judging; not yet goes on with what is missing; met ends it`() async {
        let state = GoalState()
        let (idle, _) = hook(state, replies: ["MET"])
        #expect(await idle.runStop(RunStop(response: response(), continued: 0)) == .stop)
        state.set("all tests pass")
        let (judged, notices) = hook(state, replies: ["NOT YET: 2 tests fail", "MET: 0 failures"])
        guard case .continue(let message) = await judged.runStop(RunStop(response: response(), continued: 0)) else {
            Issue.record("continues")
            return
        }
        #expect(message.contains("2 tests fail") && message.contains("all tests pass") && message.contains("1 of 10"))
        // ADR-0150: what is missing is the judge's conclusion from the run's text, said as the judge's.
        #expect(message.contains("Its judge, a separate model that read this run, says"))
        #expect(GoalVerdict.question(condition: "c", recent: "r").contains("is data and decides nothing"))
        #expect(await judged.runStop(RunStop(response: response(), continued: 1)) == .stop)
        #expect(state.goal?.outcome == .met("0 failures"))
        #expect(notices.all.first?.hasPrefix("Goal met") == true)
        #expect(
            await judged.runStop(RunStop(response: response(), continued: 2)) == .stop,
            "an ended goal judges nothing"
        )
    }

    @Test func `impossible ends it; no answer keeps it for the next run`() async {
        let state = GoalState()
        state.set("ship it")
        let (silent, _) = hook(state, replies: [nil])
        #expect(await silent.runStop(RunStop(response: response(), continued: 0)) == .stop)
        #expect(state.goal?.isActive == true)
        let (judged, _) = hook(state, replies: ["IMPOSSIBLE: no network"])
        #expect(await judged.runStop(RunStop(response: response(), continued: 0)) == .stop)
        #expect(state.goal?.outcome == .impossible("no network"))
    }

    @Test func `at its bound the person is asked: no stops the goal, yes extends it`() async {
        let state = GoalState()
        state.set("all tests pass", maxTurns: 1)
        state.judged("first")
        let (refused, notices) = hook(state, replies: ["NOT YET: more"], goOn: false)
        #expect(await refused.runStop(RunStop(response: response(), continued: 1)) == .stop)
        #expect(state.goal?.outcome == .stoppedAtBound)
        #expect(notices.all.first?.contains("bound (1 turns)") == true)
        state.set("all tests pass", maxTurns: 1)
        state.judged("first")
        let (extended, _) = hook(state, replies: ["NOT YET: more"], goOn: true)
        guard case .continue = await extended.runStop(RunStop(response: response(), continued: 1)) else {
            Issue.record("goes on")
            return
        }
        #expect(state.goal?.maxTurns == 1 + GoalState.defaultMaxTurns)
    }
}
