import TerminalKitCodecs
import TerminalKitInput
import Testing

@testable import AskTUI

/// A thread's questions are its own (roadmap 0195): kept with it while its lane is not shown, shown and answered in its lane, never
/// cleared by main's run ending; main's questions wait while a thread's lane is shown, and come back when it is left.
@Suite("A thread asks in its own lane, and main's run ending takes nothing away from it")
struct ThreadQuestionsTests {
    private let runner = RunnerInfo(name: "thread-1", detail: "look into X", id: "thread-1", kind: .agent)

    private func controller() -> ScreenController {
        var controller = ScreenController(label: "m", options: .legacy)
        controller.setScreenRows(30)
        _ = controller.handle(.runners([runner]))
        return controller
    }

    private func enter(_ controller: inout ScreenController) -> [ScreenController.Effect] {
        controller.handle(.key(KeyEvent(keyCode: Key.enter.rawValue)), pageRows: 30)
    }

    @Test func `a thread's approval waits with the thread, outlives main's run, and is answered in its lane`() {
        var controller = controller()
        _ = controller.handle(.thread(id: "thread-1", .askApproval(id: 7, question: "write asks. Allow it?")))
        #expect(controller.state.pendingApproval == nil, "not main's")
        #expect(controller.state.threads["thread-1"]?.approval?.id == 7)
        _ = controller.handle(.runEnded)
        #expect(controller.state.threads["thread-1"]?.approval?.id == 7, "main's run ending leaves it")
        _ = controller.enterLane(runner)
        #expect(controller.state.pendingApproval?.id == 7, "its lane shows it")
        let effects = enter(&controller)
        #expect(effects.contains { if case .answerApproval(7, _) = $0 { true } else { false } })
        #expect(controller.state.pendingApproval == nil)
    }

    @Test func `the model's questions in a thread take the keys in its lane`() {
        var controller = controller()
        let question = ScreenQuestion(
            question: "Which?",
            header: "Pick",
            choices: [.init(label: "a"), .init(label: "b")]
        )
        _ = controller.handle(.thread(id: "thread-1", .askQuestions(id: 9, questions: [question])))
        #expect(controller.state.pendingQuestions == nil)
        _ = controller.enterLane(runner)
        #expect(controller.state.pendingQuestions?.id == 9)
        let effects = controller.handle(.key(KeyEvent(keyCode: 0x1B)), pageRows: 30)
        #expect(
            effects.contains { if case .answerQuestions(9, nil) = $0 { true } else { false } },
            "Esc declines them, in the lane"
        )
        #expect(controller.state.lane?.id == "thread-1", "and the lane stays")
    }

    @Test func `main's approval waits while a thread's lane is shown, and comes back when it is left`() {
        var controller = controller()
        _ = controller.enterLane(runner)
        _ = controller.handle(.askApproval(id: 3, question: "main asks. Allow it?"))
        #expect(controller.state.pendingApproval == nil, "the lane's section is the thread's")
        #expect(controller.state.lane?.stashedApproval?.id == 3)
        #expect(ScreenComposer.status(for: controller.state).line.text.contains("Main is waiting for an answer"))
        controller.leaveLane()
        #expect(controller.state.pendingApproval?.id == 3)
    }

    @Test func `the thread's run ending takes away what it still asked, and only that`() {
        var controller = controller()
        _ = controller.handle(.askApproval(id: 3, question: "main asks. Allow it?"))
        _ = controller.handle(.thread(id: "thread-1", .askApproval(id: 7, question: "write asks. Allow it?")))
        _ = controller.handle(.thread(id: "thread-1", .runEnded))
        #expect(controller.state.threads["thread-1"]?.approval == nil)
        #expect(controller.state.pendingApproval?.id == 3, "main's stays")
    }
}
