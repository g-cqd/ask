import TerminalKitCodecs
import TerminalKitInput
import Testing

@testable import AskTUI

/// A question never waits unseen (roadmap 0062, step 3): while a runner's output has the transcript, the question main asked is in the status line, and the
/// answer keys work as they always do.
@Suite("A question asked while a lane is shown is in the status line and is answered from there")
struct RunnerApprovalTests {
    private func lane() -> PointerRig {
        var rig = PointerRig(columns: 80, rows: 16, lines: ["first"])
        rig.controller.handle(.runners([RunnerInfo(name: "job-1", detail: "sleep 9")]))
        rig.controller.state.runnersOpen = true
        press(Key.down.rawValue, &rig)
        press(Key.enter.rawValue, &rig)
        rig.controller.handle(.runnerOutput(id: "job-1", text: "output"))
        rig.draw()
        return rig
    }

    @discardableResult
    private func press(_ code: UInt32, _ rig: inout PointerRig) -> [ScreenController.Effect] {
        let effects = rig.controller.handle(.key(KeyEvent(keyCode: code)), pageRows: 12)
        rig.draw()
        return effects
    }

    private func status(_ rig: PointerRig) -> String {
        (0 ..< 16).map { rig.text(row: $0) }.first { $0.contains("ready") || $0.contains("y once") } ?? ""
    }

    @Test func `the question leads the status line while the lane hides main's transcript`() {
        var rig = lane()
        rig.controller.handle(.askApproval(id: 4, question: "bash wants network. Allow it?"))
        rig.draw()
        #expect(status(rig).hasPrefix("bash wants network. Allow it?  y once · a for this session · n no · "))
        #expect(rig.controller.state.lane != nil, "the lane stays: the answer needs no change of view")
    }

    @Test func `y answers it from the lane, and the line goes back to the route`() {
        var rig = lane()
        rig.controller.handle(.askApproval(id: 4, question: "Allow it?"))
        #expect(press(0x79, &rig) == [.answerApproval(id: 4, .once)])
        #expect(
            !status(rig).contains("Allow it?") && status(rig).contains("main › job-1") && status(rig).contains("ready"))
    }

    @Test func `no question, no change to the line, and main shows its question in the transcript as before`() {
        var rig = lane()
        #expect(status(rig).hasPrefix("m · ready"))
        press(0x1B, &rig)
        rig.controller.handle(.askApproval(id: 5, question: "Allow it?"))
        rig.draw()
        #expect((0 ..< 16).contains { rig.text(row: $0).hasPrefix("Allow it?  y once") })
        #expect((0 ..< 16).contains { rig.text(row: $0).hasPrefix("m · ready") }, "the status line is the plain one")
    }

    @Test func `a question from a runner shows as waiting in the strip and counts`() {
        var rig = PointerRig(columns: 80, rows: 16)
        rig.controller.handle(
            .runners([RunnerInfo(name: "review", detail: "wants to run bash", kind: .agent, state: .waitingForApproval)]
            ))
        rig.controller.state.runnersOpen = true
        rig.draw()
        let text = (0 ..< 16).map { rig.text(row: $0) }.joined(separator: "\n")
        #expect(text.contains("review  wants to run bash · waiting for approval") && text.contains("1 runner"))
    }
}
