internal import TerminalKitCodecs
internal import TerminalKitInput
internal import TerminalKitRender
internal import Testing

@testable import AskTUI

/// A click on an answer of the approval section checks it, as Space does; Enter still confirms (roadmap 0116).
@Suite("A click checks an approval answer")
struct ApprovalClickTests {
    private func rig() -> PointerRig {
        var rig = PointerRig(columns: 60, rows: 16)
        rig.controller.handle(.askApproval(id: 3, question: "bash wants network. Allow it?"))
        rig.draw()
        return rig
    }

    private func row(of text: String, in rig: PointerRig) -> Int? {
        (0 ..< rig.buffer.rows).first { rig.text(row: $0).contains(text) }
    }

    @Test func `clicking an answer checks it and moves there, without answering`() throws {
        var rig = rig()
        let target = try #require(row(of: "Allow for the session", in: rig))
        #expect(rig.click(row: target, col: 10).isEmpty)
        #expect(rig.controller.state.pendingApproval?.checked == 1 && rig.controller.state.pendingApproval?.cursor == 1)
        #expect(
            rig.controller.handle(.key(KeyEvent(keyCode: 0x0D)), pageRows: 10) == [.answerApproval(id: 3, .session)])
    }

    @Test func `clicking the question or a blank row checks nothing`() throws {
        var rig = rig()
        let question = try #require(row(of: "Allow it?", in: rig))
        _ = rig.click(row: question, col: 4)
        _ = rig.click(row: question + 1, col: 4)
        #expect(rig.controller.state.pendingApproval?.checked == 0)
    }
}
