internal import TerminalKitCodecs
internal import TerminalKitInput
internal import TerminalKitText
internal import Testing

@testable import AskTUI

/// A drag in the input that reaches its top or bottom row asks the input to scroll that way, but only while the draft goes on that
/// way; anywhere between, it asks nothing (the mutation run of 2026-11-08 found this unread).
@Suite("A drag at the input's edge scrolls it, only where there is more")
struct InputDragScrollTests {
    /// Ten lines in an input that shows six, scrolled to the end, as typing leaves it.
    private func rig() -> PointerRig {
        var rig = PointerRig(columns: 40, rows: 16, lines: ["one"])
        _ = rig.controller.handle(.paste((1 ... 10).map { "line \($0)" }.joined(separator: "\n")), pageRows: 10)
        rig.draw()
        return rig
    }

    private func dragging(_ rig: inout PointerRig, from: Int, to: Int) -> ScrollRequest? {
        rig.mouse(.left, .press, row: from, col: 4)
        rig.mouse(.left, .drag, row: to, col: 5)
        return rig.controller.inputDrag.request
    }

    @Test func `at the top row, with lines above, it asks to scroll up`() {
        var rig = rig()
        let frame = rig.controller.frame
        #expect(dragging(&rig, from: frame.promptRow + 3, to: frame.promptRow) == .up)
    }

    @Test func `at the bottom row, on the draft's last line, it asks nothing`() {
        var rig = rig()
        let frame = rig.controller.frame
        #expect(dragging(&rig, from: frame.promptRow + 2, to: frame.promptRow + frame.promptRows - 1) == nil)
    }

    @Test func `at the bottom row, with lines below, it asks to scroll down`() {
        var rig = rig()
        rig.controller.state.promptScroll = 0
        rig.draw()
        let frame = rig.controller.frame
        #expect(dragging(&rig, from: frame.promptRow + 2, to: frame.promptRow + frame.promptRows - 1) == .down)
    }

    @Test func `between the edges it asks nothing`() {
        var rig = rig()
        rig.controller.state.promptScroll = 2
        rig.draw()
        let frame = rig.controller.frame
        #expect(dragging(&rig, from: frame.promptRow + 1, to: frame.promptRow + 2) == nil)
    }
}
