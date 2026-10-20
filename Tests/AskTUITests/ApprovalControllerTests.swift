import TerminalKitCodecs
import TerminalKitInput
import Testing

@testable import AskTUI

/// The approval question in the screen: it waits for y, a or n (Esc is no), and nothing else answers it.
@Suite("An approval question waits for y, a or n, and nothing else answers it")
struct ApprovalControllerTests {
    private func key(_ text: String) -> InputEvent { .key(KeyEvent(keyCode: text.unicodeScalars.first!.value)) }

    private func asking() -> ScreenController {
        var controller = ScreenController(label: "m")
        _ = controller.handle(.paste("go"), pageRows: 10)
        _ = controller.handle(.key(KeyEvent(keyCode: 0x0D)), pageRows: 10)
        controller.handle(.askApproval(id: 7, question: "bash wants network any. Allow it?"))
        return controller
    }

    @Test(arguments: [("y", ApprovalChoice.once), ("a", .session), ("n", .deny)])
    func `the answer keys answer the question once`(answer: String, choice: ApprovalChoice) {
        var controller = asking()
        #expect(controller.handle(key(answer), pageRows: 10) == [.answerApproval(id: 7, choice)])
        #expect(controller.state.pendingApproval == nil)
        #expect(controller.handle(key(answer), pageRows: 10).isEmpty, "a second key answers nothing")
    }

    @Test func `the question is shown with how to answer it`() {
        let controller = asking()
        guard case .notice(let text, _) = controller.state.transcript.items.last else {
            Issue.record("no notice")
            return
        }
        #expect(
            text.contains("bash wants network any") && text.contains("y once") && text.contains("a for this session"))
    }

    @Test func `escape answers no rather than aborting the turn`() {
        var controller = asking()
        #expect(controller.handle(.key(KeyEvent(keyCode: 0x1B)), pageRows: 10) == [.answerApproval(id: 7, .deny)])
        #expect(controller.state.running)
    }

    @Test func `Ctrl-C still aborts the turn, and the question goes with it`() {
        var controller = asking()
        #expect(controller.handle(.key(KeyEvent(keyCode: 0x03)), pageRows: 10) == [.cancelRun])
        #expect(controller.state.pendingApproval == nil)
    }

    @Test func `other keys neither answer nor type into the prompt`() {
        var controller = asking()
        #expect(controller.handle(key("x"), pageRows: 10).isEmpty)
        #expect(controller.state.editor.text.isEmpty && controller.state.pendingApproval?.id == 7)
    }

    @Test func `the run ending clears an unanswered question`() {
        var controller = asking()
        _ = controller.handle(.runEnded)
        #expect(controller.state.pendingApproval == nil)
    }
}
