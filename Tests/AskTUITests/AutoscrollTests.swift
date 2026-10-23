internal import TerminalKitCodecs
internal import TerminalKitText
internal import Testing

@testable import AskTUI

/// A drag held at the top or bottom edge keeps scrolling and keeps selecting, though a held button reports no motion (roadmap 0051).
@Suite("A drag held at an edge scrolls and selects without further motion")
struct AutoscrollTests {
    private static let long = (1 ... 40).map { "row \($0 < 10 ? "0" : "")\($0)" }
    /// Ten transcript rows on twelve: the first is row 0 and the last is row 9.
    private func rig(_ options: ScreenOptions = ScreenOptions()) -> PointerRig {
        PointerRig(options: options, lines: Self.long)
    }

    private func selected(_ rig: PointerRig) -> String {
        rig.controller.state.selection?.text(in: TranscriptContent(rig.controller.state.transcript)) ?? ""
    }

    @Test func `holding a drag at the top scrolls to the start and the selection reaches it`() {
        var rig = rig()
        rig.mouse(.left, .press, row: 5, col: 0)
        rig.mouse(.left, .drag, row: 0, col: 0)
        #expect(rig.controller.state.scrollback == 1)
        #expect(rig.controller.isAutoscrolling)
        var ticks = 0
        while rig.tick() { ticks += 1 }
        #expect(ticks >= 25)
        #expect(!rig.controller.isAutoscrolling)
        let effects = rig.mouse(.left, .release, row: 0, col: 0)
        guard case .copy(let text) = effects.first else {
            Issue.record("nothing was copied")
            return
        }
        #expect(text.hasPrefix("row 01\nrow 02"))
        #expect(text.split(separator: "\n").count > 30)
        #expect(rig.controller.state.scrollback > 0)
    }

    @Test func `holding a drag at the bottom scrolls back to the end`() {
        var rig = rig()
        for _ in 0 ..< 10 { rig.mouse(.scrollUp, .press, row: 3, col: 3) }
        rig.mouse(.left, .press, row: 3, col: 0)
        rig.mouse(.left, .drag, row: 9, col: 5)
        while rig.tick() {}
        #expect(rig.controller.state.scrollback == 0)
        let effects = rig.mouse(.left, .release, row: 9, col: 5)
        guard case .copy(let text) = effects.first else {
            Issue.record("nothing was copied")
            return
        }
        #expect(text.hasSuffix("row 40"))
    }

    @Test func `each step shows one more line, and a step waits for the frame that shows the last one`() {
        var rig = rig()
        rig.mouse(.left, .press, row: 5, col: 0)
        rig.mouse(.left, .drag, row: 0, col: 0)
        let first = rig.controller.tick()
        #expect(first)
        #expect(rig.controller.state.scrollback == 2)
        // No frame has been drawn since: the position it would act on is not on screen yet.
        let second = rig.controller.tick()
        #expect(!second)
        #expect(rig.controller.state.scrollback == 2)
        rig.draw()
        let drawn = rig.tick()
        #expect(drawn)
        #expect(rig.controller.state.scrollback == 3)
    }

    @Test func `the selection grows by the line that scrolled into view`() {
        var rig = rig()
        rig.mouse(.left, .press, row: 5, col: 0)
        rig.mouse(.left, .drag, row: 0, col: 0)
        let before = selected(rig).split(separator: "\n").count
        rig.tick()
        rig.tick()
        #expect(selected(rig).split(separator: "\n").count == before + 2)
    }

    @Test func `releasing the button, or moving back inside, stops the timer`() {
        var rig = rig()
        rig.mouse(.left, .press, row: 5, col: 0)
        rig.mouse(.left, .drag, row: 0, col: 0)
        rig.mouse(.left, .drag, row: 5, col: 4)
        #expect(!rig.controller.isAutoscrolling)
        let idle = rig.tick()
        #expect(!idle)
        rig.mouse(.left, .drag, row: 0, col: 0)
        #expect(rig.controller.isAutoscrolling)
        rig.mouse(.left, .release, row: 0, col: 0)
        #expect(!rig.controller.isAutoscrolling)
        let scrollback = rig.controller.state.scrollback
        let afterRelease = rig.tick()
        #expect(!afterRelease)
        #expect(rig.controller.state.scrollback == scrollback)
    }

    @Test func `typing, or turning the mouse off, leaves nothing for the timer to do`() {
        var rig = rig()
        rig.mouse(.left, .press, row: 5, col: 0)
        rig.mouse(.left, .drag, row: 0, col: 0)
        rig.controller.clearSelection()
        #expect(!rig.controller.isAutoscrolling)
        var off = PointerRig(options: ScreenOptions(mouse: false), lines: Self.long)
        off.mouse(.left, .drag, row: 0, col: 0)
        let ticked = off.tick()
        #expect(!off.controller.isAutoscrolling && !ticked)
    }

    @Test func `a drag that stays at the end of the transcript has nothing more to scroll`() {
        var rig = rig()
        rig.mouse(.left, .press, row: 5, col: 0)
        rig.mouse(.left, .drag, row: 9, col: 0)
        #expect(!rig.controller.isAutoscrolling)
        let ticked = rig.tick()
        #expect(!ticked)
    }
}
