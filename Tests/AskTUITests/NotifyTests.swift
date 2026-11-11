internal import TerminalKitInput
internal import Testing

@testable import AskTUI

/// `ui.notify` on the screen (note n62; the owner's answers of 2026-11-11): while the terminal is not focused, or does not say, a
/// bell or a notification when a turn ends or ask waits for your answer; never with the setting off.
@Suite("ask tells you when it is done or waits, while you look elsewhere")
struct NotifyTests {
    private func controller(_ style: NotifyStyle) -> ScreenController {
        var options = ScreenOptions()
        options.workspace = "/src/shop"
        options.notify = style
        return ScreenController(label: "m", options: options)
    }

    private func turnEnded(_ controller: inout ScreenController) -> [String] {
        controller.state.running = true
        return controller.handle(.runEnded).compactMap { if case .notify(let text) = $0 { text } else { nil } }
    }

    @Test func `off, nothing; on, a turn's end says so while focus is not known`() {
        var off = controller(.off)
        #expect(turnEnded(&off).isEmpty)
        var on = controller(.bell)
        #expect(turnEnded(&on) == ["ask · shop: done"])
    }

    @Test func `focused, nothing; once the terminal loses focus, again`() {
        var on = controller(.notification)
        _ = on.handle(.focusIn, pageRows: 10)
        #expect(turnEnded(&on).isEmpty)
        _ = on.handle(.focusOut, pageRows: 10)
        #expect(turnEnded(&on) == ["ask · shop: done"])
    }

    @Test func `a run that did not run a turn says nothing`() {
        var on = controller(.bell)
        let effects = on.handle(.runEnded)
        #expect(!effects.contains { if case .notify = $0 { true } else { false } })
    }

    @Test func `an approval or the model's questions say ask waits for you`() {
        var on = controller(.bell)
        let asked = on.handle(.askApproval(id: 1, question: "Run make?"))
        #expect(asked.contains(.notify("ask · shop: waiting for your answer")))
        var questioned = controller(.bell)
        let question = ScreenQuestion(question: "Which?", header: "Pick", choices: [.init(label: "a")])
        #expect(
            questioned.handle(.askQuestions(id: 2, questions: [question])) == [
                .notify("ask · shop: waiting for your answer")
            ]
        )
    }

    @Test func `focus is reported only when notifications are on`() {
        var options = ScreenOptions()
        #expect(!modes(for: options).focusEvents)
        options.notify = .bell
        #expect(modes(for: options).focusEvents)
    }

    @Test(arguments: [
        (["TERM_PROGRAM": "iTerm.app"], "\u{1B}]9;ask · shop: done\u{1B}\\"),
        (["TERM_PROGRAM": "ghostty"], "\u{1B}]9;ask · shop: done\u{1B}\\"),
        (["TERM_PROGRAM": "WezTerm"], "\u{1B}]9;ask · shop: done\u{1B}\\"),
        (["TERM": "xterm-kitty"], "\u{1B}]99;;ask · shop: done\u{1B}\\"),
        (["TERM_PROGRAM": "Apple_Terminal"], "\u{07}"),
        ([:], "\u{1B}]777;notify;ask;ask · shop: done\u{1B}\\")
    ])
    func `a notification goes as the terminal reads one`(environment: [String: String], sent: String) {
        let way = TerminalNotification(style: .notification, environment: environment)
        #expect(way.sequence("ask · shop: done") == Array(sent.utf8), "\(environment)")
    }

    @Test func `a bell is a bell, and nothing in the text can end the sequence`() {
        #expect(TerminalNotification(style: .bell, environment: ["TERM_PROGRAM": "ghostty"]).sequence("x") == [0x07])
        #expect(TerminalNotification(style: .off, environment: [:]).sequence("x").isEmpty)
        let way = TerminalNotification(style: .notification, environment: [:])
        #expect(way.sequence("a;b\u{1B}\\c\u{07}") == Array("\u{1B}]777;notify;ask;a,b\\c\u{1B}\\".utf8))
    }
}
