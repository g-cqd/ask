import TerminalKitCodecs
import TerminalKitInput
import Testing

@testable import AskTUI

/// A command's question offers its subcommands and its program for the session, beside this time and deny (roadmap 0134).
@Suite("A command is allowed this time, by subcommand, or by program")
struct CommandApprovalTests {
    private func asking(_ phrases: [String], _ programs: [String]) -> ScreenController {
        var controller = ScreenController(label: "m", options: .legacy)
        controller.handle(
            .askApproval(
                id: 2, question: "bash git status. Allow it?", kind: .command(phrases: phrases, programs: programs)))
        return controller
    }

    private func answers(_ controller: ScreenController) -> [String] {
        ScreenComposer.pickerLines(for: controller.state, columns: 80, rows: 12).map(\.text)
            .filter { $0.contains("[ ]") || $0.contains("[✓]") }
    }

    private func key(_ text: String) -> InputEvent { .key(KeyEvent(keyCode: text.unicodeScalars.first!.value)) }

    @Test func `four answers: this time, the subcommand, the program, deny`() {
        var controller = asking(["git status"], ["git"])
        let rows = answers(controller)
        #expect(rows.count == 4)
        #expect(rows[0].contains("Allow this time") && rows[0].contains("[✓]"))
        #expect(rows[1].contains("Allow `git status` for the session") && rows[1].hasSuffix("a"))
        #expect(rows[2].contains("Allow `git` for the session") && rows[2].hasSuffix("p"))
        #expect(rows[3].contains("Deny"))
        _ = controller.handle(key("p"), pageRows: 10)
        #expect(controller.handle(.key(KeyEvent(keyCode: 0x0D)), pageRows: 10) == [.answerApproval(id: 2, .program)])
        guard case .notice(let text, _) = controller.state.transcript.items.last else { return #expect(Bool(false)) }
        #expect(text.hasSuffix("→ allowed `git` for the session"))
    }

    @Test func `a program with no subcommand has one session answer; an uncoverable line has none`() {
        #expect(answers(asking(["ls"], ["ls"])).count == 3)
        let none = answers(asking([], []))
        #expect(none.count == 2 && none[0].contains("Allow this time") && none[1].contains("Deny"))
    }
}
