internal import TerminalKitCodecs
internal import TerminalKitInput
internal import Testing

@testable import AskTUI

/// A command opener's question (ADR-0148) belongs to a click, not to the turn: it is always answered, so its command never waits on
/// a question nobody can see, and stopping it does not stop the model.
@Suite("An opener's question is always answered")
struct OpenerQuestionTests {
    private func asked() -> ScreenController {
        var controller = ScreenController(label: "m", options: .legacy)
        controller.handle(
            .askApproval(
                id: 7,
                question: "Run your opener for files?",
                kind: .opener(remembers: true),
                detail: "code /a"
            )
        )
        return controller
    }

    private func key(_ code: UInt32, _ modifiers: KeyModifiers = []) -> InputEvent {
        .key(KeyEvent(keyCode: code, modifiers: modifiers))
    }

    @Test func `enter allows this time, a then enter always, escape denies`() {
        var once = asked()
        #expect(once.handle(key(0x0D), pageRows: 10) == [.answerApproval(id: 7, .once)])
        var always = asked()
        _ = always.handle(key(0x61), pageRows: 10)
        #expect(always.handle(key(0x0D), pageRows: 10) == [.answerApproval(id: 7, .session)])
        var denied = asked()
        #expect(denied.handle(key(0x1B), pageRows: 10) == [.answerApproval(id: 7, .deny)])
        #expect(denied.state.pendingApproval == nil)
    }

    @Test func `control C denies it and leaves the turn alone`() {
        var controller = asked()
        controller.state.running = true
        #expect(controller.handle(key(0x63, .ctrl), pageRows: 10) == [.answerApproval(id: 7, .deny)])
        #expect(controller.state.pendingApproval == nil)
    }

    @Test func `a question that takes its place denies it, so its command does not wait for ever`() {
        var controller = asked()
        let effects = controller.handle(.askApproval(id: 8, question: "Run rm?", kind: .grant))
        #expect(effects == [.answerApproval(id: 7, .deny)])
        #expect(controller.state.pendingApproval?.id == 8)
        // A model's question is not answered for it: its run is what waits, and what cancels it.
        #expect(controller.handle(.askApproval(id: 9, question: "Again?", kind: .grant)).isEmpty)
    }
}
