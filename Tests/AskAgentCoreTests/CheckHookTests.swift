import AskAI
import Synchronization
import Testing

@testable import AskAgentCore

/// The reference `run.stop` hook (roadmap 0192): when a run that changed things would end, it runs the configured check, and sends a
/// failure's output back so the model fixes it. A pass, a check that did not finish, or a run that changed nothing ends the run.
@Suite("The check hook sends a failing check back, and only after a run changed things")
struct CheckHookTests {
    private final class Runs: Sendable {
        let count = Mutex(0)
        let outcome: CheckOutcome
        init(_ outcome: CheckOutcome) { self.outcome = outcome }
        func hook() -> CheckHook {
            CheckHook(command: "swift test") { [self] in
                count.withLock { $0 += 1 }
                return outcome
            }
        }
    }

    private func stop(changed: Bool) -> RunStop {
        RunStop(
            response: AssembledResponse(
                id: "r",
                model: "m",
                blocks: [],
                stopReason: .endTurn,
                usage: TokenUsage(),
                unrecognized: []
            ),
            continued: 0,
            changed: changed
        )
    }

    @Test func `a run that changed nothing is not checked`() async {
        let runs = Runs(.failed("boom"))
        #expect(await runs.hook().runStop(stop(changed: false)) == .stop)
        #expect(runs.count.withLock { $0 } == 0)
    }

    @Test func `a failing check is sent back with its command and output`() async {
        let runs = Runs(.failed("Test a failed\n[exit 1]"))
        let decision = await runs.hook().runStop(stop(changed: true))
        #expect(
            decision
                == .continue(
                    "The check `swift test` failed. Fix what it reports, then finish; it runs again when you do.\n\nTest a failed\n[exit 1]"
                )
        )
        #expect(runs.hook().name == "check")
    }

    @Test(arguments: [CheckOutcome.passed, .unfinished])
    func `a check that passed, or did not finish, ends the run`(outcome: CheckOutcome) async {
        #expect(await Runs(outcome).hook().runStop(stop(changed: true)) == .stop)
    }

    @Test func `a long output is cut to its end, which says what failed`() async {
        let output = String(repeating: "x", count: CheckHook.keptCharacters) + "THE END"
        guard case .continue(let message) = await Runs(.failed(output)).hook().runStop(stop(changed: true)) else {
            Issue.record("expected a continue")
            return
        }
        #expect(message.hasSuffix("THE END"))
        #expect(message.contains("…\n"))
        #expect(message.count < CheckHook.keptCharacters + 200)
    }
}
