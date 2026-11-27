internal import TerminalKitCodecs
internal import TerminalKitInput
internal import Testing

@testable import AskTUI

/// ADR-0170 (`policy.gatewayApprovals`): when `mirrorApprovalsAllowed` is false, a gateway viewer's terminal cannot answer, move or
/// cancel a pending approval; it can still scroll and unfold the command, says why once, and leaves the approval to the person at the
/// computer.
@Suite("policy.gatewayApprovals keeps remote viewers from answering approvals")
struct MirrorApprovalPolicyTests {
    private func controller(allows: Bool) -> ScreenController {
        var options = ScreenOptions.legacy
        options.mirrorApprovalsAllowed = allows
        var controller = ScreenController(label: "m", options: options)
        controller.setScreenRows(24)
        _ = controller.ask(id: 9, question: "bash asks. Allow it?", kind: .grant, detail: "rm -rf build\necho done")
        return controller
    }

    @Test func `remote keys neither answer nor cancel an approval when policy forbids it, while local keys still do`() {
        var controller = controller(allows: false)
        for code: UInt32 in [0x0D, 0x1B, 0x20, 0x79, 0x6E, 0x03, Key.down.rawValue] {
            let effects = controller.handleMirror(.key(KeyEvent(keyCode: code)), pageRows: 20)
            #expect(effects.isEmpty, "code \(code) from mirror must produce no approval effect")
        }
        #expect(controller.handleMirror(.paste("y\r"), pageRows: 20).isEmpty)
        #expect(controller.state.pendingApproval?.id == 9)
        #expect(controller.state.pendingApproval?.checked == 0)

        let notices = controller.state.transcript.items.compactMap { item -> String? in
            if case .notice(let text, _) = item { return text }
            return nil
        }
        #expect(notices.count == 1 && notices.first?.contains("policy.gatewayApprovals") == true)

        // Ctrl+O from the viewer still unfolds the command so they can read what is being asked.
        _ = controller.handleMirror(.key(KeyEvent(keyCode: 0x0F)), pageRows: 20)
        #expect(controller.state.pendingApproval?.showsWholeDetail == true)

        // Local keyboard at the computer answers normally.
        let local = controller.handle(.key(KeyEvent(keyCode: 0x0D)), pageRows: 20)
        #expect(local.count == 1 && controller.state.pendingApproval == nil)
    }

    @Test func `when policy allows it, a viewer can answer an approval`() {
        var controller = controller(allows: true)
        let effects = controller.handleMirror(.key(KeyEvent(keyCode: 0x0D)), pageRows: 20)
        #expect(effects.count == 1 && controller.state.pendingApproval == nil)
    }
}
