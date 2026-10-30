import Foundation
import TerminalKitCodecs
import TerminalKitInput
import Testing

@testable import AskTUI

/// The model's questions (roadmap 0117), in the approval section's place and style: Up and Down move, Space or a number checks while
/// the note is empty, what is typed in the input is the note, Tab and Shift+Tab change question, Enter goes on and, after the last of a
/// series, to a review that Enter sends and Esc leaves; Esc on a question declines. The draft that was in the input comes back after.
@Suite("The model's questions are a section of choices above the input")
struct QuestionSectionTests {
    private let enter = InputEvent.key(KeyEvent(keyCode: 0x0D))
    private let space = InputEvent.key(KeyEvent(keyCode: 0x20))
    private let escape = InputEvent.key(KeyEvent(keyCode: 0x1B))
    private let down = InputEvent.key(KeyEvent(keyCode: Key.down.rawValue))
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

    private func section(_ controller: ScreenController) -> [String] {
        ScreenComposer.pickerLines(for: controller.state, columns: 70, rows: 14).map(\.text)
    }

    @Test func `one question: the arrows and Space choose, Enter sends, and the draft comes back`() {
        var controller = asking([Self.scope], draft: "half a thought")
        #expect(controller.state.editor.text.isEmpty, "the input holds the note now")
        let effects = press([down, space, enter], &controller)
        #expect(effects == [.answerQuestions(id: 7, [QuestionAnswer(chosen: [1], note: "")])])
        #expect(controller.state.pendingQuestions == nil && controller.state.editor.text == "half a thought")
    }

    @Test func `the note is typed in the input, and Space types once the note has begun`() {
        var controller = asking([Self.scope])
        _ = press([space] + type("keep the api") + [enter], &controller)
        #expect(controller.state.pendingQuestions == nil)
        var again = asking([Self.scope])
        let effects = press(type("2") + type("x 1") + [enter], &again)
        #expect(
            effects == [.answerQuestions(id: 7, [QuestionAnswer(chosen: [1], note: "x 1")])],
            "a number checks while the note is empty; after that it is part of the note")
    }

    @Test func `several may be checked when the question says so, and Space unchecks`() {
        var controller = asking([Self.tests])
        let effects = press([space, down, space, space, enter], &controller)
        #expect(effects == [.answerQuestions(id: 7, [QuestionAnswer(chosen: [0], note: "")])])
    }

    @Test func `a series: each question keeps its note, Enter after the last reviews, Esc goes back, Enter sends`() {
        var controller = asking([Self.scope, Self.tests])
        _ = press(type("a") + [tab], &controller)
        #expect(controller.state.editor.text.isEmpty && controller.state.pendingQuestions?.current == 1)
        _ = press([backTab], &controller)
        #expect(controller.state.editor.text == "a")
        _ = press([enter, space, enter], &controller)
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

    @Test func `a required note holds Enter until one is typed`() {
        let why = ScreenQuestion(question: "Why?", header: "Why", choices: [], note: .required)
        var controller = asking([why])
        #expect(press([enter], &controller).isEmpty)
        #expect(section(controller).contains { $0.contains("needs a note") })
        #expect(
            press(type("speed") + [enter], &controller) == [
                .answerQuestions(id: 7, [QuestionAnswer(chosen: [], note: "speed")])
            ])
    }

    @Test func `the section shows tabs for a series only, the question, and a box per choice`() {
        let one = section(asking([Self.scope]))
        #expect(!one.contains { $0.contains("[1 Scope]") })
        #expect(one.contains { $0.contains("What should change?") })
        #expect(one.contains { $0.contains("[ ]") && $0.contains("1") && $0.contains("Only the parser") })
        #expect(one.contains { $0.contains("Everything") && $0.contains("parser and printer") })
        let series = section(asking([Self.scope, Self.tests]))
        #expect(series.contains { $0.contains("[1 Scope]") && $0.contains("2 Tests") && $0.contains("Review") })
    }

    @Test func `a run that ends while they wait takes them away and gives the draft back`() {
        var controller = asking([Self.scope], draft: "draft")
        _ = press(type("half a note"), &controller)
        controller.handle(.runEnded)
        #expect(controller.state.pendingQuestions == nil && controller.state.editor.text == "draft")
    }
}
