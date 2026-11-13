import Testing

@testable import AskAgentCore

/// `/loop` (roadmap 0228): the command's words, and the schedule's rules, checked on offsets without waiting.
@Suite("Recurring prompts")
struct RecurringPromptsTests {
    @Test func `the command reads intervals, stops and lists, and refuses the rest`() {
        #expect(RecurringCommand.parse("") == .list)
        #expect(RecurringCommand.parse("10m check CI") == .add(every: .seconds(600), prompt: "check CI"))
        #expect(RecurringCommand.parse("2h tidy  up") == .add(every: .seconds(7200), prompt: "tidy up"))
        #expect(RecurringCommand.parse("stop 3") == .stop(3))
        #expect(RecurringCommand.parse("stop all") == .stopAll)
        for refused in ["30s too fast", "10m", "10x task", "stop", "stop x", "0m task"] {
            guard case .invalid = RecurringCommand.parse(refused) else {
                Issue.record("\(refused) should be refused")
                continue
            }
        }
        #expect(
            RecurringCommand.describe(.seconds(600)) == "10 min" && RecurringCommand.describe(.seconds(86_400)) == "1 d"
        )
    }

    @Test func `a prompt is sent each interval, skipped while a turn runs, and not caught up`() {
        var loops = RecurringPrompts()
        let id = loops.add(every: .seconds(600), prompt: "check CI", now: .zero)
        #expect(loops.nextDue == .seconds(600))
        #expect(loops.tick(now: .seconds(599), turnRunning: false).isEmpty)
        #expect(loops.tick(now: .seconds(600), turnRunning: false) == [.send(id: id, prompt: "check CI", run: 1)])
        #expect(loops.tick(now: .seconds(1200), turnRunning: true) == [.skipped(id: id)])
        #expect(loops.tick(now: .seconds(5000), turnRunning: false) == [.send(id: id, prompt: "check CI", run: 2)])
        #expect(loops.nextDue == .seconds(5600), "the missed ones are not sent")
        #expect(loops.entries.first?.skipped == 1)
    }

    @Test func `an entry ends after its runs or its lifetime, and can be stopped`() {
        var loops = RecurringPrompts()
        let id = loops.add(every: .seconds(60), prompt: "x", now: .zero)
        var last: [RecurringPrompts.Tick] = []
        for minute in 1 ... RecurringPrompts.maximumRuns {
            last = loops.tick(now: .seconds(60 * minute), turnRunning: false)
        }
        #expect(last.last == .finished(id: id, runs: RecurringPrompts.maximumRuns))
        #expect(loops.entries.isEmpty)
        let old = loops.add(every: .seconds(3600), prompt: "y", now: .zero)
        #expect(loops.tick(now: RecurringPrompts.lifetime, turnRunning: true).last == .finished(id: old, runs: 0))
        let kept = loops.add(every: .seconds(60), prompt: "z", now: .zero)
        #expect(loops.remove(kept) && !loops.remove(kept))
    }
}
