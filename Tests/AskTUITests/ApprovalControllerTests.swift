import TerminalKitCodecs
import TerminalKitInput
import Testing

@testable import AskTUI

/// The approval question is a section above the input (roadmap 0116): one checkbox per answer, drawn with block characters; the arrows
/// move, Space checks, a number or a letter checks its row, Enter confirms. Esc denies at once and Ctrl+C stops the turn. Once answered,
/// the question stays in the conversation as one block with its answer.
@Suite("An approval question is a section of checkboxes above the input")
struct ApprovalControllerTests {
    private func key(_ text: String) -> InputEvent { .key(KeyEvent(keyCode: text.unicodeScalars.first!.value)) }
    private let enter = InputEvent.key(KeyEvent(keyCode: 0x0D))
    private let space = InputEvent.key(KeyEvent(keyCode: 0x20))
    private let down = InputEvent.key(KeyEvent(keyCode: Key.down.rawValue))
    private let up = InputEvent.key(KeyEvent(keyCode: Key.up.rawValue))

    private func asking(_ kind: ApprovalKind = .grant) -> ScreenController {
        var controller = ScreenController(label: "m", options: .legacy)
        _ = controller.handle(.paste("go"), pageRows: 10)
        _ = controller.handle(.key(KeyEvent(keyCode: 0x0D)), pageRows: 10)
        controller.handle(.askApproval(id: 7, question: "bash wants network any. Allow it?", kind: kind))
        return controller
    }

    private func section(_ controller: ScreenController) -> [String] {
        ScreenComposer.pickerLines(for: controller.state, columns: 60, rows: 10).map(\.text)
    }

    @Test
    func `the question and its three answers are drawn above the input, the default checked, and nothing is added yet`()
    {
        let controller = asking()
        let rows = section(controller)
        #expect(rows.count == 4)
        #expect(rows[0].contains("bash wants network any. Allow it?"))
        #expect(
            rows[1].contains("▐█▌") && rows[1].contains("1") && rows[1].contains("Allow this time")
                && rows[1].contains("y"))
        #expect(
            rows[2].contains("▐ ▌") && rows[2].contains("2") && rows[2].contains("Allow for the session")
                && rows[2].contains("a"))
        #expect(rows[3].contains("▐ ▌") && rows[3].contains("3") && rows[3].contains("Deny") && rows[3].contains("n"))
        #expect(
            controller.state.transcript.items.count == 1, "only the prompt: the question is in the section, not a block"
        )
    }

    @Test func `a long question wraps whole above its answers, which always fit`() {
        var controller = ScreenController(label: "m", options: .legacy)
        let question =
            "The MCP server fx's tool boom ({\"path\":\"/tmp/a/very/long/path/to/a/victim.txt\"}) is marked destructive. Allow it?"
        controller.handle(.askApproval(id: 1, question: question, kind: .destructive))
        let rows = ScreenComposer.pickerLines(for: controller.state, columns: 40, rows: 10).map(\.text)
        #expect(rows.suffix(3).allSatisfy { $0.contains("▐") })
        #expect(rows.dropLast(3).joined(separator: " ").contains("Allow it?"))
        #expect(rows.allSatisfy { $0.count <= 40 })
        let tight = ScreenComposer.pickerLines(for: controller.state, columns: 40, rows: 4).map(\.text)
        #expect(
            tight.count == 4 && tight.suffix(3).allSatisfy { $0.contains("▐") },
            "the answers before the question's rows")
    }

    @Test func `the arrows move, Space checks, Enter confirms`() {
        var controller = asking()
        #expect(controller.handle(down, pageRows: 10).isEmpty)
        #expect(controller.handle(space, pageRows: 10).isEmpty, "checking is not answering")
        #expect(
            section(controller)[2].contains("▐█▌") && section(controller)[1].contains("▐ ▌"),
            "one box checked at a time")
        _ = controller.handle(up, pageRows: 10)
        #expect(section(controller)[2].contains("▐█▌"), "moving does not check")
        #expect(controller.handle(enter, pageRows: 10) == [.answerApproval(id: 7, .session)])
        #expect(controller.state.pendingApproval == nil && section(controller).isEmpty)
        #expect(controller.handle(enter, pageRows: 10).isEmpty, "a second Enter answers nothing")
    }

    @Test(arguments: [
        ("y", ApprovalChoice.once), ("a", .session), ("n", .deny), ("1", .once), ("2", .session), ("3", .deny)
    ])
    func `a letter or a number checks its answer, and Enter confirms it`(shortcut: String, choice: ApprovalChoice) {
        var controller = asking()
        #expect(controller.handle(key(shortcut), pageRows: 10).isEmpty)
        #expect(controller.handle(enter, pageRows: 10) == [.answerApproval(id: 7, choice)])
    }

    @Test func `the answered question stays as one block with its answer`() {
        var controller = asking()
        _ = controller.handle(key("a"), pageRows: 10)
        _ = controller.handle(enter, pageRows: 10)
        let notices = controller.state.transcript.items.compactMap { item -> String? in
            if case .notice(let text, _) = item { return text }
            return nil
        }
        #expect(notices == ["bash wants network any. Allow it? → allowed for the session"])
    }

    @Test func `a destructive tool's question has Deny checked, so a stray Enter never allows it`() {
        var controller = asking(.destructive)
        #expect(section(controller)[3].contains("▐█▌"))
        #expect(controller.handle(enter, pageRows: 10) == [.answerApproval(id: 7, .deny)])
    }

    @Test func `a question with nothing to remember is Yes or No, No checked`() {
        var controller = asking(.confirm)
        let rows = section(controller)
        #expect(rows.count == 3 && rows[1].contains("Yes") && rows[2].contains("No") && rows[2].contains("▐█▌"))
        _ = controller.handle(key("y"), pageRows: 10)
        #expect(controller.handle(enter, pageRows: 10) == [.answerApproval(id: 7, .once)])
        guard case .notice(let text, _) = controller.state.transcript.items.last else {
            Issue.record("no block")
            return
        }
        #expect(text.hasSuffix("→ yes"))
    }

    @Test func `Esc denies at once rather than aborting the turn`() {
        var controller = asking()
        #expect(controller.handle(.key(KeyEvent(keyCode: 0x1B)), pageRows: 10) == [.answerApproval(id: 7, .deny)])
        #expect(controller.state.running)
    }

    @Test func `Ctrl-C still aborts the turn, and the question is kept as denied`() {
        var controller = asking()
        #expect(controller.handle(.key(KeyEvent(keyCode: 0x03)), pageRows: 10) == [.cancelRun])
        #expect(controller.state.pendingApproval == nil)
        #expect(
            controller.state.transcript.items.contains(
                .notice("bash wants network any. Allow it? → denied", isError: false)))
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
