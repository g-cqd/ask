import TerminalKitCodecs
import TerminalKitInput
import Testing

@testable import AskTUI

@Suite("Turn abort confirmation never makes navigation destructive")
struct TurnAbortConfirmationTests {
    private func controller() -> ScreenController {
        var controller = ScreenController(label: "test", options: ScreenOptions(abortTurnRequiresConfirmation: true))
        controller.state.running = true
        return controller
    }

    @Test func `Escape never arms or aborts a turn`() {
        var controller = controller()
        for _ in 0 ..< 3 {
            #expect(controller.handle(.key(KeyEvent(keyCode: 0x1B)), pageRows: 12).isEmpty)
        }
        #expect(controller.state.abortArmedAt == nil)
    }

    @Test func `two consecutive Ctrl C presses abort but the first only arms`() {
        var controller = controller()
        let now = ContinuousClock.now
        let first = controller.handle(.key(KeyEvent(keyCode: 3)), pageRows: 12, at: now)
        #expect(first.count == 1 && !first.contains(.cancelRun))
        #expect(controller.handle(.key(KeyEvent(keyCode: 3)), pageRows: 12, at: now + .seconds(1)) == [.cancelRun])
    }

    @Test func `another key disarms turn abortion`() {
        var controller = controller()
        let now = ContinuousClock.now
        _ = controller.handle(.key(KeyEvent(keyCode: 3)), pageRows: 12, at: now)
        _ = controller.handle(.key(KeyEvent(keyCode: 0x1B)), pageRows: 12, at: now)
        #expect(!controller.handle(.key(KeyEvent(keyCode: 3)), pageRows: 12, at: now).contains(.cancelRun))
    }

    @Test func `a new turn never inherits confirmation from the previous turn`() {
        var controller = controller()
        let now = ContinuousClock.now
        _ = controller.handle(.key(KeyEvent(keyCode: 3)), pageRows: 12, at: now)
        _ = controller.begin(.startRun("next"))
        #expect(!controller.handle(.key(KeyEvent(keyCode: 3)), pageRows: 12, at: now).contains(.cancelRun))
    }

    @Test func `expired confirmation only arms again`() {
        var controller = controller()
        let now = ContinuousClock.now
        _ = controller.handle(.key(KeyEvent(keyCode: 3)), pageRows: 12, at: now)
        #expect(
            !controller.handle(.key(KeyEvent(keyCode: 3)), pageRows: 12, at: now + .seconds(3)).contains(.cancelRun))
    }

    @Test func `the default still aborts with one press`() {
        var controller = ScreenController(label: "test")
        controller.state.running = true
        #expect(controller.handle(.key(KeyEvent(keyCode: 3)), pageRows: 12) == [.cancelRun])
    }

    @Test func `clearing a draft does not arm confirmation`() {
        var controller = controller()
        _ = controller.handle(.key(KeyEvent(keyCode: 0x61)), pageRows: 12)
        #expect(controller.handle(.key(KeyEvent(keyCode: 3)), pageRows: 12).isEmpty)
        #expect(controller.state.editor.text.isEmpty && controller.state.abortArmedAt == nil)
    }

    @Test func `a completed focused job stays visible when auto return is disabled`() {
        var controller = ScreenController(label: "test", options: ScreenOptions(jobAutoReturnWhenFocused: false))
        let runner = RunnerInfo(name: "job-1", detail: "build")
        controller.handle(.runners([runner]))
        _ = controller.enterLane(runner)
        controller.handle(.runnerOutput(id: runner.id, text: "finished output"))
        controller.handle(.runners([]))
        #expect(controller.state.lane?.id == runner.id)
        #expect(controller.state.transcript.items.count > 0)
        #expect(controller.escapePressed().isEmpty)
        #expect(controller.state.lane == nil)
    }
}
