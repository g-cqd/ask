import Foundation
import TerminalKitRender
import TerminalKitStyle
import TerminalKitText
import Testing

@testable import AskTUI

/// A choice's explanation wraps instead of clipping at the right edge (note n5): beside the labels when the terminal has room, below
/// the label on a narrow screen; every wrapped row is dimmed and maps back to that choice when clicked.
@Suite("Question choice explanations wrap in the terminal")
struct QuestionChoiceWrapTests {
    private static let longDetail =
        "keeps the existing public contract unchanged and isolates the rewrite to the internal scanner"

    private func pending(choices: [ScreenQuestion.Choice], note: ScreenQuestion.Note = .optional) -> PendingQuestions {
        PendingQuestions(
            id: 1,
            questions: [ScreenQuestion(question: "How?", header: "Plan", choices: choices, note: note)]
        )
    }

    @Test func `a long explanation wraps under its own column, dimmed, with no line wider than the screen`() throws {
        let pending = pending(choices: [
            .init(label: "Narrow", detail: Self.longDetail), .init(label: "Full", detail: "short")
        ])
        let columns = 60
        let laid = ScreenComposer.questionLayout(pending, columns: columns, rows: 30)
        let lines = laid.lines
        let first = try #require(lines.firstIndex { $0.text.contains("Narrow") })
        let full = try #require(lines.firstIndex { $0.text.contains("Full") })
        #expect(full > first + 1, "the explanation took more than one row")
        let detailColumn = try #require(lines[first].text.firstRange(of: "keeps")).lowerBound
            .utf16Offset(in: lines[first].text)
        let parts: [String] = (first ..< full)
            .map { index in
                let text = lines[index].text
                return index == first
                    ? String(text.dropFirst(detailColumn))
                    : text.trimmingCharacters(in: .whitespaces)
            }
        let joined = parts.joined(separator: " ")
        #expect(joined == Self.longDetail, "nothing clipped: \(joined)")
        for index in first + 1 ..< full {
            #expect(
                lines[index].text.hasPrefix(String(repeating: " ", count: detailColumn)),
                "indented under the explanation"
            )
            #expect(lines[index].style == Style(dim: true))
            #expect(UnicodeWidth.displayWidth(of: lines[index].text) <= columns)
        }
        let bodyIndices = (first ..< full).map { $0 - laid.choices.lowerBound }
        #expect(bodyIndices.allSatisfy { laid.choiceRows[$0] == 0 }, "every wrapped row belongs to choice 0")
        #expect(laid.choiceRows[full - laid.choices.lowerBound] == 1)
    }

    @Test func `on a narrow screen, the explanation wraps below the label instead of squeezing beside it`() throws {
        let pending = pending(choices: [.init(label: "A very long choice label", detail: Self.longDetail)], note: .none)
        let columns = 40
        let laid = ScreenComposer.questionLayout(pending, columns: columns, rows: 30)
        let first = try #require(laid.lines.firstIndex { $0.text.contains("A very long choice label") })
        #expect(!laid.lines[first].text.contains("keeps"), "not squeezed onto the label row")
        let extra = laid.lines[(first + 1)...].prefix { $0.style == Style(dim: true) && !$0.text.contains("Enter") }
        #expect(extra.count >= 3, "wrapped across several rows")
        let joined = extra.map { $0.text.trimmingCharacters(in: .whitespaces) }.joined(separator: " ")
        #expect(joined == Self.longDetail, "whole explanation shown: \(joined)")
        for row in extra {
            #expect(UnicodeWidth.displayWidth(of: row.text) <= columns)
        }
    }

    @Test func `clicking a wrapped explanation row checks that choice, and clicking the second choice still checks it`()
        throws
    {
        var rig = PointerRig(columns: 60, rows: 20)
        rig.controller.handle(
            .askQuestions(
                id: 7,
                questions: [
                    ScreenQuestion(
                        question: "How?",
                        header: "Plan",
                        choices: [
                            .init(label: "Narrow", detail: Self.longDetail),
                            .init(label: "Full", detail: "rewrites both sides")
                        ]
                    )
                ]
            )
        )
        rig.draw()
        let find = { (needle: String) -> Int? in (0 ..< rig.buffer.rows).first { rig.text(row: $0).contains(needle) } }
        let continuation = try #require(find("scanner"))
        let fullRow = try #require(find("Full"))
        let noteRow = try #require(find("Note"))
        #expect(fullRow > continuation, "continuation row sits between choice 0 and choice 1")
        _ = rig.click(row: fullRow, col: 10)
        #expect(rig.controller.state.pendingQuestions?.chosen[0] == [1], "shifted second choice still checks choice 1")
        _ = rig.click(row: continuation, col: 25)
        #expect(rig.controller.state.pendingQuestions?.chosen[0] == [0], "clicking the wrapped row checks choice 0")
        _ = rig.click(row: noteRow, col: 10)
        #expect(rig.controller.state.pendingQuestions?.focus == .note, "clicking Note still focuses the note")
    }
}
