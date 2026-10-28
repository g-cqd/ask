import TerminalKitCodecs
import TerminalKitInput
import Testing

@testable import AskTUI

@Suite("Esc, Ctrl+C and the queue behind an interrupted turn follow their settings (roadmap 0083)")
struct InterruptSettingsTests {
    private let esc = InputEvent.key(KeyEvent(keyCode: 0x1B))
    private let ctrlC = InputEvent.key(KeyEvent(keyCode: 3))

    private func running(_ options: ScreenOptions = ScreenOptions()) -> ScreenController {
        var controller = ScreenController(label: "test", options: options)
        _ = controller.begin(.startRun("go"))
        return controller
    }

    @Test func `by default Esc needs two presses to stop a turn`() {
        var controller = running()
        let now = ContinuousClock.now
        #expect(!controller.handle(esc, pageRows: 12, at: now).contains(.cancelRun))
        #expect(controller.state.abortArmedAction == "Esc")
        #expect(controller.handle(esc, pageRows: 12, at: now + .seconds(1)) == [.cancelRun])
    }

    @Test func `the second Esc after the window only arms again`() {
        var controller = running()
        let now = ContinuousClock.now
        _ = controller.handle(esc, pageRows: 12, at: now)
        #expect(!controller.handle(esc, pageRows: 12, at: now + .seconds(3)).contains(.cancelRun))
    }

    @Test func `with confirmation off one Esc stops the turn`() {
        var controller = running(ScreenOptions(escapeInterruptRequiresConfirmation: false))
        #expect(controller.handle(esc, pageRows: 12) == [.cancelRun])
    }

    @Test func `Esc does not stop a turn when only Ctrl+C is allowed`() {
        var controller = running(ScreenOptions(interruptKeys: .ctrlC, escapeInterruptRequiresConfirmation: false))
        #expect(controller.handle(esc, pageRows: 12).isEmpty)
        #expect(controller.handle(ctrlC, pageRows: 12) == [.cancelRun])
    }

    @Test func `Ctrl+C does not stop a turn when only Esc is allowed`() {
        var controller = running(ScreenOptions(interruptKeys: .esc))
        #expect(!controller.handle(ctrlC, pageRows: 12).contains(.cancelRun))
        #expect(controller.state.running)
    }

    @Test func `Esc first steps back out of a lane or strip before it can stop a turn`() {
        var controller = running(ScreenOptions(escapeInterruptRequiresConfirmation: false))
        controller.state.runnersOpen = true
        #expect(controller.handle(esc, pageRows: 12).isEmpty)
        #expect(!controller.state.runnersOpen)
        #expect(controller.handle(esc, pageRows: 12) == [.cancelRun])
    }

    private func interrupted(_ setting: QueuedAfterInterrupt) -> (ScreenController, [ScreenController.Effect]) {
        var controller = running(ScreenOptions(interruptSendsQueued: setting))
        _ = controller.queue("one", followUp: false)
        _ = controller.queue("two", followUp: false)
        _ = controller.handle(ctrlC, pageRows: 12)
        let effects = controller.handle(.runEnded)
        return (controller, effects)
    }

    @Test func `all: the first queued message starts a turn and the others join it`() {
        let (controller, effects) = interrupted(.all)
        guard case .startRun("one") = effects.first else {
            Issue.record("expected a run for the first message, got \(effects)")
            return
        }
        #expect(effects.count == 2)
        #expect(controller.state.running && controller.state.editor.text.isEmpty)
    }

    @Test func `next: only the first starts, and the other waits unsent`() {
        var (controller, effects) = interrupted(.next)
        #expect(effects == [.startRun("one")])
        #expect(controller.pending.map(\.text) == ["two"])
        #expect(controller.handle(.runEnded) == [.startRun("two")])
    }

    @Test func `none: the queue returns to the input`() {
        let (controller, effects) = interrupted(.none)
        #expect(effects.isEmpty)
        #expect(controller.state.editor.text == "one\n\ntwo")
    }

    @Test func `a failed turn still returns the queue to the input`() {
        var controller = running(ScreenOptions(interruptSendsQueued: .all))
        _ = controller.queue("one", followUp: false)
        _ = controller.handle(.returnQueuedPrompts)
        #expect(controller.handle(.runEnded).isEmpty)
        #expect(controller.state.editor.text == "one")
    }
}
