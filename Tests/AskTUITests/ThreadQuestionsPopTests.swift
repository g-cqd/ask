import TerminalKitCodecs
import TerminalKitInput
import Testing

@testable import AskTUI

/// Where a thread's question appears (`threads.questions`, note n19): at once where the person is (`focus`), after a delay
/// (`after`), or only in its lane (`lane`). Main's own question comes first; answering a popped question answers the thread's.
@Suite("A thread's question pops up where the person is, after a while, or only in its lane")
struct ThreadQuestionsPopTests {
    private let thread = RunnerInfo(name: "thread-1", detail: "look", id: "thread-1", kind: .agent)

    private func controller(_ mode: ThreadQuestionsMode) -> ScreenController {
        var options = ScreenOptions.legacy
        options.threadQuestions = mode
        var controller = ScreenController(label: "m", options: options)
        controller.setScreenRows(30)
        _ = controller.handle(.runners([thread]))
        return controller
    }

    private func asks(_ controller: inout ScreenController, id: Int = 7) {
        _ = controller.handle(.thread(id: "thread-1", .askApproval(id: id, question: "write asks. Allow it?")))
    }

    @Test func `focus: it shows at once in main, named, and answering it answers the thread`() {
        var controller = controller(.focus)
        asks(&controller)
        #expect(controller.state.pendingApproval?.id == 7)
        #expect(controller.state.pendingApproval?.question.hasPrefix("thread-1: ") == true)
        let effects = controller.handle(.key(KeyEvent(keyCode: Key.enter.rawValue)), pageRows: 30)
        #expect(effects.contains { if case .answerApproval(7, _) = $0 { true } else { false } })
        #expect(controller.state.pendingApproval == nil && controller.state.threads["thread-1"]?.approval == nil)
    }

    @Test func `focus: main's own question comes first, and the thread's follows once it is answered`() {
        var controller = controller(.focus)
        _ = controller.handle(.askApproval(id: 3, question: "main asks. Allow it?"))
        asks(&controller)
        #expect(controller.state.pendingApproval?.id == 3)
        _ = controller.handle(.key(KeyEvent(keyCode: 0x1B)), pageRows: 30)
        #expect(controller.state.pendingApproval?.id == 7, "then the thread's")
    }

    @Test func `focus: opening the thread's lane shows it there once, and leaving takes nothing of it into main`() {
        var controller = controller(.focus)
        asks(&controller)
        _ = controller.enterLane(thread)
        #expect(controller.state.pendingApproval?.id == 7 && controller.state.lane?.stashedApproval == nil)
        #expect(controller.state.pendingApproval?.question.hasPrefix("thread-1: ") == false, "in its own lane, unnamed")
    }

    @Test func `lane: it stays in its lane`() {
        var controller = controller(.lane)
        asks(&controller)
        #expect(controller.state.pendingApproval == nil && controller.state.threads["thread-1"]?.approval?.id == 7)
    }

    @Test func `after: not at once, then once its delay has passed`() {
        var controller = controller(.after(.seconds(30)))
        let start = ContinuousClock.now
        asks(&controller)
        #expect(controller.state.pendingApproval == nil)
        controller.threadQuestionDelayEnded(at: start + .seconds(31))
        #expect(controller.state.pendingApproval?.id == 7)
    }

    @Test func `a thread's run ending takes its popped question away`() {
        var controller = controller(.focus)
        asks(&controller)
        _ = controller.handle(.thread(id: "thread-1", .runEnded))
        #expect(controller.state.pendingApproval == nil)
    }
}
