import TerminalKitCodecs
import TerminalKitInput
import TerminalKitRender
import TerminalKitStyle
import Testing

@testable import AskTUI

/// Focus on a runner (roadmap 0062, step 2): keys move through the strip, Enter shows a runner's output in place of the conversation, and Esc steps back.
@Suite("The strip is reached by Down, a runner is focused by Enter, and Esc goes back one step at a time")
struct RunnerLaneTests {
    private static let jobs = [
        RunnerInfo(name: "job-1", detail: "npm run dev"), RunnerInfo(name: "job-2", detail: "tail -f log")
    ]

    private func rig(runners: [RunnerInfo] = RunnerLaneTests.jobs) -> PointerRig {
        var rig = PointerRig(columns: 60, rows: 16, lines: ["first", "second"])
        rig.controller.handle(.runners(runners))
        rig.controller.state.runnersOpen = true
        rig.draw()
        return rig
    }

    @discardableResult
    private func press(_ code: UInt32, _ rig: inout PointerRig) -> [ScreenController.Effect] {
        let effects = rig.controller.handle(.key(KeyEvent(keyCode: code)), pageRows: 12)
        rig.draw()
        return effects
    }

    private func type(_ text: String, _ rig: inout PointerRig) {
        for scalar in text.unicodeScalars { press(scalar.value, &rig) }
    }

    private func screen(_ rig: PointerRig) -> String { (0 ..< 16).map { rig.text(row: $0) }.joined(separator: "\n") }

    @Test func `Down from an empty draft selects the first runner and the strip shows it`() {
        var rig = rig()
        press(Key.down.rawValue, &rig)
        #expect(rig.controller.state.stripSelection == "job-1")
        #expect(rig.buffer[rig.controller.frame.stripFirstRow, 0].style.bold)
        #expect(!rig.buffer[rig.controller.frame.stripFirstRow + 1, 0].style.bold)
    }

    @Test func `Down from the end of a draft enters, and Down from the middle of one does not`() {
        var rig = rig()
        type("two words", &rig)
        press(Key.left.rawValue, &rig)
        press(Key.down.rawValue, &rig)
        #expect(rig.controller.state.stripSelection == nil)
        press(Key.right.rawValue, &rig)
        press(Key.down.rawValue, &rig)
        #expect(rig.controller.state.stripSelection == "job-1")
        #expect(rig.controller.state.editor.text == "two words")
    }

    @Test func `with the strip closed or empty Down is not taken`() {
        var closed = rig()
        closed.controller.state.runnersOpen = false
        press(Key.down.rawValue, &closed)
        #expect(closed.controller.state.stripSelection == nil)
        var none = rig(runners: [])
        none.controller.state.runnersOpen = true
        press(Key.down.rawValue, &none)
        #expect(none.controller.state.stripSelection == nil)
    }

    @Test func `Up and Down move and stop at the ends`() {
        var rig = rig()
        press(Key.down.rawValue, &rig)
        press(Key.up.rawValue, &rig)
        #expect(rig.controller.state.stripSelection == "job-1")
        press(Key.down.rawValue, &rig)
        press(Key.down.rawValue, &rig)
        #expect(rig.controller.state.stripSelection == "job-2")
    }

    @Test func `any other key gives the keys back to the input and is typed there`() {
        var rig = rig()
        press(Key.down.rawValue, &rig)
        press(0x61, &rig)
        #expect(rig.controller.state.stripSelection == nil && rig.controller.state.editor.text == "a")
    }

    @Test func `Enter focuses the runner: its output replaces the conversation, and the route is in the status line`() {
        var rig = rig()
        press(Key.down.rawValue, &rig)
        press(Key.down.rawValue, &rig)
        let effects = press(Key.enter.rawValue, &rig)
        #expect(effects == [.readRunnerOutput(id: "job-2")])
        #expect(screen(rig).contains("job-2 · reading its output…") && !screen(rig).contains("second"))
        rig.controller.handle(.runnerOutput(id: "job-2", text: "listening on 8080\nGET /"))
        rig.draw()
        #expect(screen(rig).contains("listening on 8080") && screen(rig).contains("GET /"))
        #expect(screen(rig).contains("main › job-2 · esc returns"))
        #expect(rig.controller.state.stripSelection == nil)
    }

    @Test func `output for a runner that is not the one shown is ignored`() {
        var rig = rig()
        press(Key.down.rawValue, &rig)
        press(Key.enter.rawValue, &rig)
        rig.controller.handle(.runnerOutput(id: "job-2", text: "not mine"))
        rig.draw()
        #expect(!screen(rig).contains("not mine"))
        var main = self.rig()
        main.controller.handle(.runnerOutput(id: "job-1", text: "nobody asked"))
        main.draw()
        #expect(!screen(main).contains("nobody asked") && screen(main).contains("second"))
    }

    @Test func `Esc goes back one step at a time and keeps the draft and the turn`() {
        var rig = rig()
        rig.controller.state.running = true
        type("draft", &rig)
        press(Key.down.rawValue, &rig)
        press(Key.enter.rawValue, &rig)
        rig.controller.handle(.runnerOutput(id: "job-1", text: "output"))
        press(Key.down.rawValue, &rig)
        #expect(rig.controller.state.stripSelection == "job-1")
        #expect(press(0x1B, &rig).isEmpty)
        #expect(
            rig.controller.state.stripSelection == nil && rig.controller.state.lane != nil, "first, back to the input")
        press(0x1B, &rig)
        #expect(rig.controller.state.lane == nil && screen(rig).contains("second"), "then back to main")
        #expect(rig.controller.state.runnersOpen)
        press(0x1B, &rig)
        #expect(!rig.controller.state.runnersOpen, "then the strip closes")
        #expect(rig.controller.state.editor.text == "draft" && rig.controller.state.running)
    }

    @Test func `leaving a lane restores the conversation and where it was scrolled`() {
        var rig = PointerRig(columns: 60, rows: 16, lines: (1 ... 60).map { "line \($0)" })
        rig.controller.handle(.runners(Self.jobs))
        rig.controller.state.runnersOpen = true
        rig.controller.state.scrollback = 12
        let before = rig.controller.state.transcript
        press(Key.down.rawValue, &rig)
        press(Key.enter.rawValue, &rig)
        #expect(rig.controller.state.scrollback == 0)
        press(0x1B, &rig)
        #expect(rig.controller.state.transcript == before && rig.controller.state.scrollback == 12)
        rig.draw()
        #expect(!screen(rig).contains("reading its output"))
    }

    @Test func `what the run says while a lane is shown goes to main and is there when it returns`() {
        var rig = rig()
        press(Key.down.rawValue, &rig)
        press(Key.enter.rawValue, &rig)
        rig.controller.handle(.runnerOutput(id: "job-1", text: "output"))
        rig.controller.handle(.assistantText("an answer meanwhile"))
        rig.draw()
        #expect(screen(rig).contains("output") && !screen(rig).contains("an answer meanwhile"))
        press(0x1B, &rig)
        #expect(screen(rig).contains("an answer meanwhile"))
    }

    @Test func `a focused runner that ends returns to main with a notice, never to a blank lane`() {
        var rig = rig()
        press(Key.down.rawValue, &rig)
        press(Key.enter.rawValue, &rig)
        rig.controller.handle(.runners([Self.jobs[1]]))
        rig.draw()
        #expect(rig.controller.state.lane == nil)
        #expect(screen(rig).contains("job-1 is no longer running; back to main.") && screen(rig).contains("second"))
    }

    @Test func `sending a message while a lane is shown goes to main, and shows main`() {
        var rig = rig()
        press(Key.down.rawValue, &rig)
        press(Key.enter.rawValue, &rig)
        type("hello", &rig)
        let effects = press(Key.enter.rawValue, &rig)
        #expect(effects == [.startRun("hello")])
        #expect(rig.controller.state.lane == nil && screen(rig).contains("second"))
    }

    @Test func `a click on a row focuses it as Enter does, and a click elsewhere on the strip does not`() {
        var rig = rig()
        let first = rig.controller.frame.stripFirstRow
        let effects = rig.click(row: first + 1, col: 4)
        #expect(effects == [.readRunnerOutput(id: "job-2")])
        #expect(rig.controller.state.lane?.id == "job-2")
    }

    @Test func `with the mouse off the keys still do everything`() {
        var rig = PointerRig(
            columns: 60, rows: 16,
            options: ScreenOptions(mouse: false, prompt: "ask> ", tint: false, separator: false, padding: false),
            lines: ["first"])
        rig.controller.handle(.runners(Self.jobs))
        rig.controller.state.runnersOpen = true
        rig.draw()
        press(Key.down.rawValue, &rig)
        #expect(press(Key.enter.rawValue, &rig) == [.readRunnerOutput(id: "job-1")])
    }

    @Test func `a lane's lines are never mistaken for the conversation's by the layout cache`() {
        var rig = rig()
        press(Key.down.rawValue, &rig)
        press(Key.enter.rawValue, &rig)
        rig.controller.handle(.runnerOutput(id: "job-1", text: "alpha"))
        rig.draw()
        press(0x1B, &rig)
        press(Key.down.rawValue, &rig)
        press(Key.down.rawValue, &rig)
        press(Key.enter.rawValue, &rig)
        rig.controller.handle(.runnerOutput(id: "job-2", text: "bravo"))
        rig.draw()
        #expect(screen(rig).contains("bravo") && !screen(rig).contains("alpha") && !screen(rig).contains("second"))
    }

    @Test func `the selected row stays in the window when there are more runners than rows`() {
        let many = (1 ... 9).map { RunnerInfo(name: "job-\($0)", detail: "work") }
        var rig = rig(runners: many)
        for _ in 0 ..< 9 { press(Key.down.rawValue, &rig) }
        #expect(rig.controller.state.stripSelection == "job-9")
        #expect(rig.controller.frame.stripIDs.contains("job-9") && rig.controller.frame.stripIDs.count == 4)
    }
}
