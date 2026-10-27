import TerminalKitStyle
import Testing

@testable import AskTUI

@Suite("Status indicators represent activity with stable spinner styles")
struct StatusSpinnerLifetimeTests {
    @Test func `random configuration renders a cached turn style without choosing during layout`() {
        var state = ScreenState(label: "test")
        state.running = true
        state.transcript.spinnerStyle = .random
        state.statusSpinner = .braille
        for frame in 0 ..< 30 {
            state.statusFrame = frame
            let expected = SpinnerStyle.braille.frames[frame % SpinnerStyle.braille.frames.count]
            for _ in 0 ..< 5 { #expect(ScreenComposer.leadingMark(for: state).character == expected) }
        }
    }

    @Test func `a random tool spinner supplies the same frame to the header and status`() {
        let start = ContinuousClock.now
        var state = ScreenState(label: "test")
        state.running = true
        state.transcript.spinnerStyle = .random
        state.transcript.startTool(name: "bash", summary: "build", at: start)
        for frame in 0 ..< 30 {
            state.statusFrame = frame + 3
            state.transcript.advanceProgress(at: start + .seconds(frame + 1))
            #expect(ScreenComposer.leadingMark(for: state).character == state.transcript.progress[0]?.indicator)
        }
    }

    @Test func `a finished tool does not freeze the status spinner while the model is still running`() {
        let start = ContinuousClock.now
        var state = ScreenState(label: "test")
        state.running = true
        state.statusSpinner = .braille
        state.transcript.spinnerStyle = .random
        state.transcript.startTool(name: "bash", summary: "build", at: start)
        state.transcript.finishTool(.succeeded, at: start + .seconds(2))
        for frame in 0 ..< 10 {
            state.statusFrame = frame
            #expect(ScreenComposer.leadingMark(for: state).character == SpinnerStyle.braille.frames[frame])
        }
    }

    @Test func `starting a turn resolves one concrete style and resets its frame`() {
        var controller = ScreenController(label: "test", options: ScreenOptions(spinner: .random))
        controller.state.statusFrame = 99
        _ = controller.begin(.startRun("hello"))
        #expect(controller.state.statusFrame == 0)
        #expect(SpinnerStyle.allConcrete.contains(controller.state.statusSpinner))
    }

    @Test(arguments: [true, false])
    func `idle always shows a colored exclamation fallback`(sandboxed: Bool) {
        let mark = StatusLeadingMark.mark(running: false, sandboxed: sandboxed, frame: "|")
        #expect(mark.character == "!")
        #expect(mark.style?.fg == (sandboxed ? StatusLeadingMark.sandboxed.fg : StatusLeadingMark.warning.fg))
    }
}
