internal import TerminalKitCodecs
internal import TerminalKitInput
internal import Testing

@testable import AskTUI

/// `/continue`, the bare words that mean it, and Right pressed twice send one fixed message (roadmaps 0097 and 0112).
@Suite("Telling the model to continue")
struct ContinueTests {
    private let sent = ScreenController.continueText

    private func submit(_ line: String, to controller: inout ScreenController) -> [ScreenController.Effect] {
        for character in line {
            _ = controller.handle(.key(KeyEvent(keyCode: character.unicodeScalars.first!.value)), pageRows: 10)
        }
        return controller.handle(.key(KeyEvent(keyCode: 0x0D)), pageRows: 10)
    }

    private func right(
        _ controller: inout ScreenController, at offset: Duration, type: KeyEventType = .press
    ) -> [ScreenController.Effect] {
        controller.handle(
            .key(KeyEvent(keyCode: Key.right.rawValue, eventType: type)), pageRows: 10,
            at: ContinuousClock.now.advanced(by: offset)
        )
    }

    @Test func `the commands and bare words start a turn with the same message, case and spaces aside`() {
        for line in ["/continue", "continue", "Continue", "  resume ", "go ahead", "GO", "go"] {
            var controller = ScreenController(label: "m", options: ScreenOptions())
            #expect(submit(line, to: &controller) == [.startRun(sent)], "\(line)")
            #expect(controller.state.transcript.items.last == .user(sent), "\(line)")
        }
    }

    @Test func `a sentence that starts with one of the words is still a prompt`() {
        for line in ["go to the store", "continue with the tests", "resume the build please", "going"] {
            var controller = ScreenController(label: "m", options: ScreenOptions())
            #expect(submit(line, to: &controller) == [.startRun(line)], "\(line)")
        }
    }

    @Test func `the command takes extra words, and while a turn runs it is queued like any message`() {
        var controller = ScreenController(label: "m", options: ScreenOptions())
        #expect(submit("/continue but check the tests", to: &controller) == [.startRun(sent + " but check the tests")])
        var running = ScreenController(label: "m", options: ScreenOptions())
        _ = submit("first", to: &running)
        #expect(submit("continue", to: &running) == [.queuePrompt(id: 0, text: sent, followUp: false)])
    }

    @Test func `the command is listed with the others`() {
        let controller = ScreenController(label: "m", options: ScreenOptions())
        #expect(controller.commands.contains { $0.name == "continue" })
    }

    @Test func `Right twice on an empty input, not running, sends it; once or slowly does not`() {
        var controller = ScreenController(label: "m", options: ScreenOptions())
        #expect(right(&controller, at: .zero).isEmpty)
        #expect(right(&controller, at: .milliseconds(200)) == [.startRun(sent)])
        var slow = ScreenController(label: "m", options: ScreenOptions())
        _ = right(&slow, at: .zero)
        #expect(right(&slow, at: .seconds(2)).isEmpty, "too slow is a first tap again")
        #expect(right(&slow, at: .seconds(2) + .milliseconds(100)) == [.startRun(sent)])
    }

    @Test func `Right keeps its meaning elsewhere: with text, while running, another key between, or a held key`() {
        var typed = ScreenController(label: "m", options: ScreenOptions())
        _ = submit("ab", to: &typed)  // submitted and running; type again to have a draft
        var draft = ScreenController(label: "m", options: ScreenOptions())
        for character in "ab" {
            _ = draft.handle(.key(KeyEvent(keyCode: character.unicodeScalars.first!.value)), pageRows: 10)
        }
        _ = right(&draft, at: .zero)
        #expect(right(&draft, at: .milliseconds(100)).isEmpty && draft.state.editor.text == "ab")

        _ = right(&typed, at: .zero)
        #expect(right(&typed, at: .milliseconds(100)).isEmpty, "a turn is running")

        var between = ScreenController(label: "m", options: ScreenOptions())
        _ = right(&between, at: .zero)
        _ = between.handle(.key(KeyEvent(keyCode: Key.left.rawValue)), pageRows: 10)
        #expect(right(&between, at: .milliseconds(100)).isEmpty)

        var held = ScreenController(label: "m", options: ScreenOptions())
        _ = right(&held, at: .zero)
        #expect(right(&held, at: .milliseconds(30), type: .repeat).isEmpty, "auto-repeat is not a second tap")
    }
}
