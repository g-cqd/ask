import TerminalKitCodecs
import TerminalKitInput
import TerminalKitRender
import Testing

@testable import AskTUI

/// Collapsing in the runner strip, and what happens to a selection whose runner goes away.
@Suite("Left and Right close and open a parent in the strip, and a vanished runner is not selected")
struct RunnerCollapseTests {
    private static let jobs = [
        RunnerInfo(name: "job-1", detail: "npm run dev"), RunnerInfo(name: "job-2", detail: "tail")
    ]

    private func rig(runners: [RunnerInfo]) -> PointerRig {
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

    private func screen(_ rig: PointerRig) -> String { (0 ..< 16).map { rig.text(row: $0) }.joined(separator: "\n") }

    @Test func `Left closes a parent and says how many are hidden, Right opens it, Down skips the hidden`() {
        let tree = [
            RunnerInfo(name: "review", detail: "reading", kind: .agent),
            RunnerInfo(name: "explore", detail: "grep", parentID: "review", kind: .agent),
            RunnerInfo(name: "deeper", detail: "ls", parentID: "explore", kind: .agent),
            RunnerInfo(name: "job-1", detail: "sleep")
        ]
        var rig = rig(runners: tree)
        press(Key.down.rawValue, &rig)
        press(Key.left.rawValue, &rig)
        #expect(screen(rig).contains("review  reading · running · 2 hidden") && !screen(rig).contains("explore"))
        press(Key.down.rawValue, &rig)
        #expect(rig.controller.state.stripSelection == "job-1")
        press(Key.up.rawValue, &rig)
        press(Key.right.rawValue, &rig)
        #expect(screen(rig).contains("explore") && screen(rig).contains("  deeper") && !screen(rig).contains("hidden"))
        press(Key.down.rawValue, &rig)
        press(Key.down.rawValue, &rig)
        press(Key.left.rawValue, &rig)
        #expect(rig.controller.state.stripSelection == "explore", "Left on a leaf goes to its parent")
    }

    @Test func `Left on a parent that is already closed goes up to its parent`() {
        let tree = [
            RunnerInfo(name: "review", detail: "reading", kind: .agent),
            RunnerInfo(name: "explore", detail: "grep", parentID: "review", kind: .agent),
            RunnerInfo(name: "deeper", detail: "ls", parentID: "explore", kind: .agent)
        ]
        var rig = rig(runners: tree)
        press(Key.down.rawValue, &rig)
        press(Key.down.rawValue, &rig)
        press(Key.left.rawValue, &rig)
        #expect(
            rig.controller.state.collapsedRunners == ["explore"] && rig.controller.state.stripSelection == "explore")
        press(Key.left.rawValue, &rig)
        #expect(rig.controller.state.stripSelection == "review" && rig.controller.state.collapsedRunners == ["explore"])
    }

    @Test func `a selected runner that goes away leaves nothing selected`() {
        var rig = rig(runners: Self.jobs)
        press(Key.down.rawValue, &rig)
        press(Key.down.rawValue, &rig)
        rig.controller.handle(.runners([Self.jobs[0]]))
        #expect(rig.controller.state.stripSelection == nil)
    }
}
