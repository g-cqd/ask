import Foundation
import TerminalKitCodecs
import TerminalKitInput
import Testing

@testable import AskTUI

/// The model's questions (roadmap 0117, as redesigned by the owner on 2026-10-31), in the approval section's place: Tab moves the focus
/// between the tabs, the choices and the note row; the arrows highlight; Space selects; the note is a row of the question that takes
/// typing only when focused; Enter goes on and, after the last of a series, to a review that Enter sends and Esc leaves; Esc on a
/// question declines. The input below keeps its draft throughout.
@Suite("The model's questions are a section of choices and a note above the input")
struct QuestionSectionTests {
    private let enter = InputEvent.key(KeyEvent(keyCode: 0x0D))
    private let space = InputEvent.key(KeyEvent(keyCode: 0x20))
    private let escape = InputEvent.key(KeyEvent(keyCode: 0x1B))
    private let down = InputEvent.key(KeyEvent(keyCode: Key.down.rawValue))
    private let up = InputEvent.key(KeyEvent(keyCode: Key.up.rawValue))
    private let right = InputEvent.key(KeyEvent(keyCode: Key.right.rawValue))
    private let left = InputEvent.key(KeyEvent(keyCode: Key.left.rawValue))
    private let tab = InputEvent.key(KeyEvent(keyCode: 0x09))
    private let backTab = InputEvent.key(KeyEvent(keyCode: 0x09, modifiers: .shift))

    private static let scope = ScreenQuestion(
        question: "What should change?", header: "Scope",
        choices: [.init(label: "Only the parser"), .init(label: "Everything", detail: "parser and printer")])
    private static let tests = ScreenQuestion(
        question: "Which tests?", header: "Tests", choices: [.init(label: "Unit"), .init(label: "Probes")],
        multiple: true)

    private func asking(_ questions: [ScreenQuestion], draft: String = "") -> ScreenController {
        var controller = ScreenController(label: "m", options: .legacy)
        _ = controller.handle(.paste("go"), pageRows: 10)
        _ = controller.handle(enter, pageRows: 10)
        if !draft.isEmpty { _ = controller.handle(.paste(draft), pageRows: 10) }
        controller.handle(.askQuestions(id: 7, questions: questions))
        return controller
    }

    private func press(_ events: [InputEvent], _ controller: inout ScreenController) -> [ScreenController.Effect] {
        events.flatMap { controller.handle($0, pageRows: 10) }
    }

    private func type(_ text: String) -> [InputEvent] {
        text.unicodeScalars.map { .key(KeyEvent(keyCode: $0.value)) }
    }

    private func section(_ controller: ScreenController, columns: Int = 70) -> [String] {
        ScreenComposer.pickerLines(for: controller.state, columns: columns, rows: 20).map(\.text)
    }

    @Test func `one question: the arrows and Space choose, Enter sends, and the input keeps its draft throughout`() {
        var controller = asking([Self.scope], draft: "half a thought")
        #expect(controller.state.editor.text == "half a thought", "the input is not the note any more")
        let effects = press([down, space, enter], &controller)
        #expect(effects == [.answerQuestions(id: 7, [QuestionAnswer(chosen: [1], note: "")])])
        #expect(controller.state.pendingQuestions == nil && controller.state.editor.text == "half a thought")
    }

    @Test func `typing reaches the note only when it is focused`() {
        var controller = asking([Self.scope], draft: "draft")
        _ = press(type("xyz"), &controller)
        #expect(controller.state.pendingQuestions?.notes[0].text == "" && controller.state.editor.text == "draft")
        _ = press([tab] + type("keep the api"), &controller)
        #expect(controller.state.pendingQuestions?.focus == .note)
        #expect(controller.state.pendingQuestions?.notes[0].text == "keep the api", "Space types in the note")
        #expect(controller.state.editor.text == "draft")
        let effects = press([enter], &controller)
        #expect(effects == [.answerQuestions(id: 7, [QuestionAnswer(chosen: [], note: "keep the api")])])
    }

    @Test func `a number checks a choice, and Down from the last choice reaches the note, Up comes back`() {
        var controller = asking([Self.scope])
        _ = press(type("2"), &controller)
        #expect(controller.state.pendingQuestions?.chosen[0] == [1])
        _ = press([down, down], &controller)
        #expect(controller.state.pendingQuestions?.focus == .note)
        _ = press(type("1") + [up], &controller)
        #expect(controller.state.pendingQuestions?.focus == .choices)
        #expect(controller.state.pendingQuestions?.notes[0].text == "1", "a number on the note row is text")
    }

    @Test func `several may be checked when the question says so, and Space unchecks`() {
        var controller = asking([Self.tests])
        let effects = press([space, down, space, space, enter], &controller)
        #expect(effects == [.answerQuestions(id: 7, [QuestionAnswer(chosen: [0], note: "")])])
    }

    @Test func `round marks for one choice, square boxes for several`() {
        var single = asking([Self.scope])
        _ = press([space], &single)
        let one = section(single)
        #expect(one.contains { $0.contains("(•)") && $0.contains("Only the parser") })
        #expect(one.contains { $0.contains("( )") && $0.contains("Everything") })
        #expect(!one.contains { $0.contains("[ ]") || $0.contains("[✓]") })
        var several = asking([Self.tests])
        _ = press([space], &several)
        let many = section(several)
        #expect(many.contains { $0.contains("[✓]") && $0.contains("Unit") })
        #expect(many.contains { $0.contains("[ ]") && $0.contains("Probes") })
    }

    @Test func `Tab cycles the tabs, the choices and the note, and on the tabs the arrows change question`() {
        var controller = asking([Self.scope, Self.tests])
        #expect(controller.state.pendingQuestions?.focus == .choices)
        _ = press([tab], &controller)
        #expect(controller.state.pendingQuestions?.focus == .note)
        _ = press([tab], &controller)
        #expect(controller.state.pendingQuestions?.focus == .tabs)
        _ = press([right], &controller)
        #expect(controller.state.pendingQuestions?.current == 1)
        _ = press([left], &controller)
        #expect(controller.state.pendingQuestions?.current == 0)
        _ = press([tab], &controller)
        #expect(controller.state.pendingQuestions?.focus == .choices)
        _ = press([backTab, backTab], &controller)
        #expect(controller.state.pendingQuestions?.focus == .note)
    }

    @Test func `a series: each question keeps its note, Enter after the last reviews, Esc goes back, Enter sends`() {
        var controller = asking([Self.scope, Self.tests])
        _ = press([tab] + type("a") + [enter], &controller)
        #expect(controller.state.pendingQuestions?.current == 1)
        #expect(controller.state.pendingQuestions?.focus == .choices, "a question opens on its choices")
        _ = press([space, enter], &controller)
        #expect(controller.state.pendingQuestions?.reviewing == true)
        #expect(section(controller).contains { $0.contains("Scope") && $0.contains("note: a") })
        _ = press([escape], &controller)
        #expect(
            controller.state.pendingQuestions?.reviewing == false && controller.state.pendingQuestions?.current == 1)
        let effects = press([enter, enter], &controller)
        #expect(
            effects == [
                .answerQuestions(id: 7, [QuestionAnswer(chosen: [], note: "a"), QuestionAnswer(chosen: [0], note: "")])
            ])
    }

    @Test func `Esc on a question declines them all`() {
        var controller = asking([Self.scope, Self.tests], draft: "draft")
        #expect(press([escape], &controller) == [.answerQuestions(id: 7, nil)])
        #expect(controller.state.pendingQuestions == nil && controller.state.editor.text == "draft")
    }

    @Test func `a question without choices opens on its note, and a required note holds Enter until one is typed`() {
        let why = ScreenQuestion(question: "Why?", header: "Why", choices: [], note: .required)
        var controller = asking([why])
        #expect(controller.state.pendingQuestions?.focus == .note)
        #expect(press([enter], &controller).isEmpty)
        #expect(section(controller).contains { $0.contains("needs a note") })
        #expect(
            press(type("speed") + [enter], &controller) == [
                .answerQuestions(id: 7, [QuestionAnswer(chosen: [], note: "speed")])
            ])
    }

    @Test func `the section shows unnumbered tabs for a series only, the question, the choices, then the note row`() {
        let one = section(asking([Self.scope]))
        #expect(!one.contains { $0.contains("Scope") })
        #expect(one.contains { $0.contains("What should change?") })
        #expect(one.contains { $0.contains("Everything") && $0.contains("parser and printer") })
        let choice = one.firstIndex { $0.contains("Everything") }
        let note = one.firstIndex { $0.contains("Note") }
        #expect(choice != nil && note != nil && note! > choice!, "the note row follows the last choice: \(one)")
        let series = section(asking([Self.scope, Self.tests]))
        #expect(series.contains { $0.contains("[Scope]") && $0.contains("Tests") && $0.contains("Review") })
        #expect(!series.contains { $0.contains("1 Scope") || $0.contains("2 Tests") })
    }

    @Test func `a long note wraps, indented with the choices`() {
        var controller = asking([Self.scope])
        _ = press([tab] + type(String(repeating: "word ", count: 20)), &controller)
        let rows = section(controller, columns: 40)
        let first = rows.firstIndex { $0.contains("Note") }
        #expect(first != nil)
        guard let first else { return }
        let indent = rows[first].prefix { $0 == " " }.count
        #expect(rows[first + 1].hasPrefix(String(repeating: " ", count: indent)) && rows[first + 1].contains("word"))
        #expect(rows.allSatisfy { $0.count <= 40 })
    }

    @Test func `a run that ends while they wait takes them away and leaves the draft`() {
        var controller = asking([Self.scope], draft: "draft")
        _ = press([tab] + type("half a note"), &controller)
        controller.handle(.runEnded)
        #expect(controller.state.pendingQuestions == nil && controller.state.editor.text == "draft")
    }
}
