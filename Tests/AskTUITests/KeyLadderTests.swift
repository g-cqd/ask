internal import TerminalKitCodecs
internal import TerminalKitInput
internal import Testing

@testable import AskTUI

/// The keys of roadmap 0064: Esc is navigation only, and Ctrl+C is a ladder with one step a press that never quits on the first.
@Suite("Ctrl+C erases, then stops, then arms the quit; Escape never stops anything")
struct KeyLadderTests {
    private let start = ContinuousClock.now

    private func press(_ code: UInt32, _ screen: inout ScreenController, at offset: Duration = .zero)
        -> [ScreenController.Effect]
    {
        screen.handle(.key(KeyEvent(keyCode: code)), pageRows: 10, at: start + offset)
    }

    private func type(_ text: String, _ screen: inout ScreenController) {
        for scalar in text.unicodeScalars { _ = press(scalar.value, &screen) }
    }

    private func running() -> ScreenController {
        var screen = ScreenController(label: "m")
        type("go", &screen)
        _ = press(0x0D, &screen)
        return screen
    }

    @Test func `Escape with a turn running does nothing to the turn, the draft or the session`() {
        var screen = running()
        type("draft", &screen)
        #expect(press(0x1B, &screen).isEmpty)
        #expect(screen.state.running && screen.state.editor.text == "draft")
        #expect(screen.state.transcript.items.last.map { "\($0)".contains("Stopping") } != true)
    }

    @Test func `Ctrl-C with text erases the whole draft and does not stop or quit`() {
        var screen = running()
        type("one\ntwo", &screen)
        #expect(press(0x03, &screen).isEmpty)
        #expect(screen.state.editor.text.isEmpty && screen.state.running)
        #expect(screen.state.quitArmedAt == nil, "erasing is not arming")
    }

    @Test func `with an empty input and a turn running Ctrl-C stops it`() {
        var screen = running()
        #expect(press(0x03, &screen) == [.cancelRun])
    }

    @Test func `with text and a turn running it takes two presses: erase, then stop`() {
        var screen = running()
        type("steer", &screen)
        #expect(press(0x03, &screen).isEmpty)
        #expect(press(0x03, &screen) == [.cancelRun])
    }

    @Test func `idle, the first Ctrl-C only arms the quit and says so; the second within two seconds quits`() {
        var screen = ScreenController(label: "m")
        #expect(press(0x03, &screen) == [.armQuitTimer(generation: 1)])
        #expect(screen.state.quitArmedAt != nil)
        let line = ScreenComposer.status(for: screen.state).line.text
        #expect(line.contains("press Ctrl+C again to quit"))
        #expect(press(0x03, &screen, at: .milliseconds(1_900)) == [.quit])
    }

    @Test func `a second Ctrl-C after the window arms again instead of quitting`() {
        var screen = ScreenController(label: "m")
        _ = press(0x03, &screen)
        #expect(press(0x03, &screen, at: .milliseconds(2_100)) == [.armQuitTimer(generation: 2)])
    }

    @Test func `any other key between the two presses disarms the quit`() {
        for key: UInt32 in [0x61, 0x1B, 0x0D, Key.up.rawValue, Key.pageUp.rawValue] {
            var screen = ScreenController(label: "m")
            _ = press(0x03, &screen)
            _ = press(key, &screen, at: .milliseconds(100))
            #expect(screen.state.quitArmedAt == nil, "key \(key)")
        }
    }

    @Test func `the timer's end clears the hint, and an old timer cannot clear a newer window`() {
        var screen = ScreenController(label: "m")
        _ = press(0x03, &screen)
        _ = press(0x1B, &screen)
        _ = press(0x03, &screen, at: .milliseconds(500))
        screen.quitWindowEnded(generation: 1)
        #expect(screen.state.quitArmedAt != nil, "the first window's timer is stale")
        screen.quitWindowEnded(generation: 2)
        #expect(screen.state.quitArmedAt == nil)
    }

    @Test func `a selection still takes Ctrl-C to copy, and that is not an arming press`() {
        var rig = PointerRig(lines: ["alpha beta"])
        rig.drag(from: (9, 0), to: (9, 4))
        #expect(rig.controller.handle(.key(KeyEvent(keyCode: 0x03)), pageRows: 10) == [.copy("alpha")])
        #expect(rig.controller.state.quitArmedAt == nil)
    }

    @Test func `a question keeps Ctrl-C as deny and stop`() {
        var screen = running()
        screen.handle(.askApproval(id: 3, question: "Allow?"))
        #expect(press(0x03, &screen) == [.cancelRun])
        #expect(screen.state.pendingApproval == nil)
    }

    @Test func `after a key was typed Ctrl-C erases it instead of quitting`() {
        var screen = ScreenController(label: "m")
        _ = press(0x03, &screen)
        _ = press(0x61, &screen, at: .milliseconds(100))
        #expect(press(0x03, &screen, at: .milliseconds(200)).isEmpty)
        #expect(screen.state.editor.text.isEmpty)
    }

    @Test func `stopping a turn is not arming the quit`() {
        var screen = running()
        _ = press(0x03, &screen)
        #expect(screen.state.quitArmedAt == nil, "stopping is not arming")
    }
}
