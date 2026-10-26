import TerminalKitCodecs
import TerminalKitInput
import TerminalKitRender
import Testing

@testable import AskTUI

@Suite("The runner strip lives below the one input, and Escape closes it without touching the draft")
struct RunnerStripTests {
    @Test func `tasks opens the strip below the input with the status between them`() {
        var rig = PointerRig(columns: 60, rows: 14, lines: ["one", "two"])
        rig.controller.handle(.runners([RunnerInfo(name: "job-1", detail: "sleep 9")]))
        rig.controller.state.runnersOpen = true
        rig.controller.state.editor.paste("draft")
        rig.draw()
        #expect(rig.text(row: 10) == "two")
        #expect(rig.text(row: 11) == "ask> draft")
        #expect(rig.text(row: 12).contains("1 job"))
        #expect(rig.text(row: 13).hasPrefix("job-1"))
        #expect(rig.controller.frame.promptRow == 11)
        #expect(rig.controller.frame.statusRow == 12)
    }

    @Test func `Escape closes the strip and keeps the draft and the running turn`() {
        var rig = PointerRig(columns: 60, rows: 14)
        rig.controller.handle(.runners([RunnerInfo(name: "job-1", detail: "sleep 9")]))
        rig.controller.state.runnersOpen = true
        rig.controller.state.running = true
        rig.controller.state.editor.paste("draft")
        let effects = rig.controller.handle(.key(KeyEvent(keyCode: 0x1B)), pageRows: 11)
        #expect(effects.isEmpty)
        #expect(!rig.controller.state.runnersOpen)
        #expect(rig.controller.state.editor.text == "draft" && rig.controller.state.running)
    }
}
