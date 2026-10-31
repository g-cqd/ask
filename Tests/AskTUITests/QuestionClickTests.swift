internal import Foundation
internal import TerminalKitCodecs
internal import TerminalKitInput
internal import TerminalKitRender
internal import Testing

@testable import AskTUI

/// A click on one of the model's choices checks it, as Space does, a click on the note row focuses it, and a click on a tab shows that
/// question or the review (roadmap 0117); Enter still answers.
@Suite("Clicks on the model's questions")
struct QuestionClickTests {
    private static let questions = [
        ScreenQuestion(
            question: "What should change?", header: "Scope", choices: [.init(label: "Parser"), .init(label: "All")]),
        ScreenQuestion(
            question: "Which tests?", header: "Tests", choices: [.init(label: "Unit"), .init(label: "Probes")],
            multiple: true)
    ]

    private func rig() -> PointerRig {
        var rig = PointerRig(columns: 70, rows: 20)
        rig.controller.handle(.askQuestions(id: 4, questions: Self.questions))
        rig.draw()
        return rig
    }

    private func find(_ text: String, in rig: PointerRig) -> (row: Int, col: Int)? {
        for row in 0 ..< rig.buffer.rows {
            if let range = rig.text(row: row).range(of: text) {
                return (row, rig.text(row: row).distance(from: rig.text(row: row).startIndex, to: range.lowerBound))
            }
        }
        return nil
    }

    @Test func `clicking a choice checks it, and Enter answers with it`() throws {
        var rig = rig()
        let all = try #require(find("All", in: rig))
        #expect(rig.click(row: all.row, col: all.col).isEmpty)
        #expect(rig.controller.state.pendingQuestions?.chosen[0] == [1])
        #expect(rig.controller.state.pendingQuestions?.cursors[0] == 1)
    }

    @Test func `clicking the note row focuses it, and typing then goes there`() throws {
        var rig = rig()
        let note = try #require(find("Note", in: rig))
        _ = rig.click(row: note.row, col: note.col)
        #expect(rig.controller.state.pendingQuestions?.focus == .note)
        _ = rig.controller.handle(.key(KeyEvent(keyCode: UInt32(Character("x").asciiValue!))), pageRows: 10)
        #expect(rig.controller.state.pendingQuestions?.notes[0].text == "x")
    }

    @Test func `clicking a tab shows that question, and the last tab the review`() throws {
        var rig = rig()
        let tests = try #require(find("Tests", in: rig))
        _ = rig.click(row: tests.row, col: tests.col + 1)
        #expect(rig.controller.state.pendingQuestions?.current == 1)
        rig.draw()
        let review = try #require(find("Review", in: rig))
        _ = rig.click(row: review.row, col: review.col)
        #expect(rig.controller.state.pendingQuestions?.reviewing == true)
        rig.draw()
        let scope = try #require(find("Scope", in: rig))
        _ = rig.click(row: scope.row, col: scope.col + 1)
        #expect(
            rig.controller.state.pendingQuestions?.reviewing == false
                && rig.controller.state.pendingQuestions?.current == 0)
    }
}
