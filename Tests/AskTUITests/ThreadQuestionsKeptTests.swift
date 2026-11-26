import TerminalKitCodecs
import TerminalKitInput
import Testing

@testable import AskTUI

/// A thread's question shown where the person is (`threads.questions` `focus`) says which thread asks, and keeps what the person
/// did to it while the conversations go on updating (owner, 2026-11-26): every update takes the question off and puts it back.
@Suite("A popped thread question names its thread and keeps the person's answer across updates")
struct ThreadQuestionsKeptTests {
    private let thread = RunnerInfo(name: "thread-1", detail: "look", id: "thread-1", kind: .agent)

    private func controller() -> ScreenController {
        var options = ScreenOptions.legacy
        options.threadQuestions = .focus
        var controller = ScreenController(label: "m", options: options)
        controller.setScreenRows(30)
        _ = controller.handle(.runners([thread]))
        return controller
    }

    private func key(_ code: UInt32, _ controller: inout ScreenController) {
        _ = controller.handle(.key(KeyEvent(keyCode: code)), pageRows: 30)
    }

    private func type(_ text: String, _ controller: inout ScreenController) {
        for scalar in text.unicodeScalars { key(scalar.value, &controller) }
    }

    private static let question = ScreenQuestion(
        question: "Which scope?",
        header: "Scope",
        choices: [.init(label: "parser"), .init(label: "all")]
    )

    @Test func `the question names the thread that asks`() throws {
        var controller = controller()
        _ = controller.handle(.thread(id: "thread-1", .askQuestions(id: 4, questions: [Self.question])))
        let pending = try #require(controller.state.pendingQuestions)
        #expect(pending.askedBy == "thread-1")
        let lines = ScreenComposer.questionLines(pending, columns: 60, rows: 20)
        #expect(lines.first?.text.contains("thread-1 asks") == true)
    }

    @Test func `a choice and a note typed stay while main and the thread keep updating`() throws {
        var controller = controller()
        _ = controller.handle(.thread(id: "thread-1", .askQuestions(id: 4, questions: [Self.question])))
        key(Key.down.rawValue, &controller)
        key(0x20, &controller)
        key(0x09, &controller)
        type("keep the API", &controller)
        _ = controller.handle(.assistantText("main goes on"))
        _ = controller.handle(.thread(id: "thread-1", .assistantText("the thread goes on")))
        let pending = try #require(controller.state.pendingQuestions)
        #expect(pending.answers.first?.chosen == [1])
        #expect(pending.answers.first?.note == "keep the API")
        #expect(pending.askedBy == "thread-1", "still named after the updates")
        #expect(controller.state.threads["thread-1"]?.questions?.askedBy == nil, "the thread's own copy is not named")
    }

    @Test func `an approval's highlighted answer stays across an update`() {
        var controller = controller()
        _ = controller.handle(.thread(id: "thread-1", .askApproval(id: 7, question: "write asks. Allow it?")))
        key(Key.down.rawValue, &controller)
        key(0x20, &controller)
        _ = controller.handle(.assistantText("main goes on"))
        #expect(controller.state.pendingApproval?.checked == 1)
        #expect(controller.state.pendingApproval?.cursor == 1)
    }
}
