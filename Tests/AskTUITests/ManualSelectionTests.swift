internal import TerminalKitCodecs
internal import TerminalKitInput
internal import Testing

@testable import AskTUI

@Suite("Selection has keyboard copy and does not activate what is underneath")
struct ManualSelectionTests {
    private let controlC = KeyEvent(keyCode: 0x63, modifiers: .ctrl)
    private let escape = KeyEvent(keyCode: 0x1B)

    @Test func `control C copies a selection with copy on select off and consumes it`() {
        var rig = PointerRig(
            options: ScreenOptions(copyOnSelect: false, prompt: "ask> ", tint: false, separator: false, padding: false),
            lines: ["alpha beta"])
        #expect(rig.drag(from: (9, 0), to: (9, 4)).isEmpty)
        let effects = rig.controller.handle(.key(controlC), pageRows: 10)
        #expect(effects == [.copy("alpha")])
        #expect(rig.controller.state.selection == nil)
        #expect(rig.controller.state.editor.text.isEmpty)
        #expect(
            rig.controller.handle(.key(controlC), pageRows: 10) == [.armQuitTimer(generation: 1)],
            "the next press only arms the quit")
    }

    @Test func `legacy control C copies during a run instead of aborting it`() {
        var rig = PointerRig(lines: ["alpha beta"])
        rig.drag(from: (9, 0), to: (9, 4))
        rig.controller.state.running = true
        #expect(rig.controller.handle(.key(KeyEvent(keyCode: 0x03)), pageRows: 10) == [.copy("alpha")])
        #expect(rig.controller.state.running)
        #expect(rig.controller.handle(.key(controlC), pageRows: 10) == [.cancelRun])
    }

    @Test func `escape clears the selection and leaves a running turn alone`() {
        var rig = PointerRig(lines: ["alpha beta"])
        rig.drag(from: (9, 0), to: (9, 4))
        rig.controller.state.running = true
        #expect(rig.controller.handle(.key(escape), pageRows: 10).isEmpty)
        #expect(rig.controller.state.selection == nil)
        #expect(rig.controller.handle(.key(escape), pageRows: 10).isEmpty)
        #expect(rig.controller.state.running)
    }

    @Test func `an approval question still gives control C its abort meaning`() {
        var rig = PointerRig(lines: ["alpha beta"])
        rig.drag(from: (9, 0), to: (9, 4))
        rig.controller.state.running = true
        rig.controller.handle(.askApproval(id: 7, question: "Allow?"))
        #expect(rig.controller.handle(.key(controlC), pageRows: 10) == [.cancelRun])
        #expect(rig.controller.state.pendingApproval == nil)
    }

    @Test func `a click inside a selected folded header clears it without opening the block`() {
        var rig = tool()
        rig.drag(from: (9, 0), to: (9, 5))
        #expect(rig.click(row: 9, col: 3).isEmpty)
        #expect(rig.controller.state.transcript.isFolded(0))
        #expect(rig.controller.state.selection == nil)
    }

    @Test func `a click outside the selection still opens the folded block`() {
        var rig = tool()
        rig.drag(from: (9, 0), to: (9, 5))
        rig.click(row: 9, col: 12)
        #expect(!rig.controller.state.transcript.isFolded(0))
        #expect(rig.controller.state.selection == nil)
    }

    private func tool() -> PointerRig {
        PointerRig(updates: [.toolStarted(name: "bash", summary: "ls"), .toolFinished(.succeeded, output: "one\ntwo")])
    }
}
