import TerminalKitCodecs
import TerminalKitInput
import TerminalKitRender
import Testing

@testable import AskTUI

/// The approval section shows the call's whole command (roadmap 0157): folded to one row, unfolded with Ctrl+O or a click, with a blank
/// row after it; and an answered question leaves no block in the conversation, only the tool's own.
@Suite("The approval shows the whole command and leaves no block")
struct ApprovalCommandTests {
    private let command =
        "git add .\ngit commit -m 'a very long message that goes on and on past the edge of the screen'\ngit push"

    private func asking(_ detail: String? = nil) -> ScreenController {
        var controller = ScreenController(label: "m", options: .legacy)
        _ = controller.handle(.paste("go"), pageRows: 10)
        _ = controller.handle(.key(KeyEvent(keyCode: 0x0D)), pageRows: 10)
        controller.handle(
            .askApproval(
                id: 4, question: "bash: allow it?", kind: .command(phrases: ["git add"], programs: ["git"]),
                detail: detail ?? command))
        return controller
    }

    private func rows(_ controller: ScreenController, columns: Int = 50) -> [String] {
        ScreenComposer.pickerLines(for: controller.state, columns: columns, rows: 16).map(\.text)
    }

    private let ctrlO = InputEvent.key(KeyEvent(keyCode: 0x0F))

    @Test func `folded, the command is one row, cut, saying how much more there is, then a blank row`() {
        let shown = rows(asking())
        #expect(shown[0].contains("bash: allow it?"))
        #expect(shown[1].contains("git add .") && shown[1].contains("+2 lines") && shown[1].count <= 50)
        #expect(shown[2].isEmpty, "a blank row right after the command")
        #expect(shown[3].contains("[✓]"))
    }

    @Test func `Ctrl+O unfolds it whole, every line wrapped, and folds it again`() {
        var controller = asking()
        _ = controller.handle(ctrlO, pageRows: 10)
        let open = rows(controller)
        let text = open.joined(separator: " ")
        #expect(
            text.contains("git commit -m") && text.contains("past the edge of the screen'") && text.contains("git push")
        )
        #expect(open.allSatisfy { $0.count <= 50 })
        #expect(!text.contains("+2 lines"))
        let blank = open.firstIndex { $0.isEmpty }
        #expect(blank.map { open[$0 + 1].contains("[✓]") } == true, "the blank row stays right after the command")
        _ = controller.handle(ctrlO, pageRows: 10)
        #expect(rows(controller) == rows(asking()))
    }

    @Test func `a short command is shown whole, with no hint`() {
        let shown = rows(asking("ls -la"))
        #expect(shown[1].hasSuffix("ls -la") && !shown[1].contains("lines"))
    }

    @Test func `answering leaves no block, whatever the answer`() {
        for key: UInt32 in [0x0D, 0x1B, 0x03] {
            var controller = asking()
            let before = controller.state.transcript.items
            _ = controller.handle(.key(KeyEvent(keyCode: key)), pageRows: 10)
            #expect(controller.state.pendingApproval == nil)
            #expect(controller.state.transcript.items == before, "key \(key)")
        }
    }

    @Test func `a click on the command unfolds it`() throws {
        var rig = PointerRig(columns: 60, rows: 20)
        rig.controller.handle(
            .askApproval(
                id: 4, question: "bash: allow it?", kind: .command(phrases: ["git add"], programs: ["git"]),
                detail: command))
        rig.draw()
        let row = try #require((0 ..< rig.buffer.rows).first { rig.text(row: $0).contains("+2 lines") })
        _ = rig.click(row: row, col: 6)
        #expect(rig.controller.state.pendingApproval?.showsWholeDetail == true)
    }
}
