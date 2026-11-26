import TerminalKitCodecs
import TerminalKitInput
import Testing

@testable import AskTUI

/// A thread's lane is a conversation as main is (owner, 2026-11-26): while its thread works, Esc and Ctrl+C interrupt it with main's
/// confirmation, Ctrl+B sends what it waits on to the background, and Esc goes back to main once it is idle or main waits for an answer.
@Suite("Esc, Ctrl+C and Ctrl+B act on a working thread in its lane as on main's turn")
struct ThreadLaneKeysTests {
    private func runner(_ state: RunnerInfo.State) -> RunnerInfo {
        RunnerInfo(name: "thread-1", detail: "look", id: "thread-1", kind: .agent, state: state)
    }

    private func inLane(_ state: RunnerInfo.State = .running) -> ScreenController {
        var options = ScreenOptions.legacy
        options.threadQuestions = .lane
        options.abortTurnRequiresConfirmation = true
        options.escapeInterruptRequiresConfirmation = true
        var controller = ScreenController(label: "m", options: options)
        controller.setScreenRows(30)
        _ = controller.handle(.runners([runner(state)]))
        _ = controller.enterLane(runner(state))
        return controller
    }

    private func press(_ code: UInt32, _ controller: inout ScreenController) -> [ScreenController.Effect] {
        controller.handle(.key(KeyEvent(keyCode: code)), pageRows: 30)
    }

    @Test func `Esc twice stops the working thread and keeps its lane`() {
        var controller = inLane()
        #expect(press(0x1B, &controller).contains { if case .armQuitTimer = $0 { true } else { false } })
        #expect(controller.state.lane?.id == "thread-1")
        #expect(press(0x1B, &controller) == [.stopThread(id: "thread-1")])
    }

    @Test func `Ctrl+C asks for the same confirmation as main's turn`() {
        var controller = inLane()
        #expect(!press(0x03, &controller).contains(.stopThread(id: "thread-1")))
        #expect(press(0x03, &controller) == [.stopThread(id: "thread-1")])
    }

    @Test func `Esc in an idle thread's lane goes back to main`() {
        var controller = inLane(.done)
        _ = press(0x1B, &controller)
        #expect(controller.state.lane == nil)
    }

    @Test func `Esc goes back to main when main waits for an answer`() {
        var controller = inLane()
        _ = controller.onMain { $0.ask(id: 3, question: "main asks. Allow it?") }
        _ = press(0x1B, &controller)
        #expect(controller.state.lane == nil && controller.state.pendingApproval?.id == 3)
    }

    @Test func `Ctrl+B sends the thread's running command to the background`() {
        var controller = inLane()
        _ = controller.handle(
            .thread(id: "thread-1", .toolStarted(name: "bash", summary: "sleep", id: "c", command: ToolCommand()))
        )
        #expect(press(0x02, &controller) == [.sendThreadCommandToBackground(id: "thread-1")])
    }

    @Test func `Ctrl+B ends main's wait on a job`() {
        var controller = ScreenController(label: "m", commands: [])
        _ = controller.handle(.paste("go"), pageRows: 10)
        _ = controller.handle(.key(KeyEvent(keyCode: Key.enter.rawValue)), pageRows: 10)
        controller.handle(.toolStarted(name: "job", summary: "wait job-1", id: "w"))
        #expect(press(0x02, &controller) == [.sendCommandToBackground])
    }
}
