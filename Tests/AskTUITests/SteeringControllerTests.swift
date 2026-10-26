import TerminalKitCodecs
import TerminalKitInput
import Testing

@testable import AskTUI

@Suite("Queued prompts survive completion races and aborts")
struct SteeringControllerTests {
    private func submit(_ text: String, to controller: inout ScreenController, followUp: Bool = false)
        -> [ScreenController.Effect]
    {
        _ = controller.handle(.paste(text), pageRows: 10)
        return controller.handle(
            .key(KeyEvent(keyCode: 0x0D, modifiers: followUp ? .alt : [])), pageRows: 10)
    }

    @Test func `busy Enter steers and Alt-Enter follows up without showing an unrecorded user message`() {
        var controller = ScreenController(label: "m", options: .legacy)
        _ = submit("Start", to: &controller)
        #expect(submit("Now", to: &controller) == [.queuePrompt(id: 0, text: "Now", followUp: false)])
        #expect(
            submit("Later", to: &controller, followUp: true) == [.queuePrompt(id: 1, text: "Later", followUp: true)])
        #expect(
            controller.state.transcript.items.filter {
                if case .user = $0 { return true }
                return false
            } == [.user("Start")])
        controller.handle(.promptAccepted(id: 0, text: "Now"))
        #expect(controller.state.transcript.items.last == .user("Now"))
    }

    @Test func `a submission after the final boundary starts once when runEnded arrives`() {
        var controller = ScreenController(label: "m", options: .legacy)
        _ = submit("Start", to: &controller)
        _ = submit("Late", to: &controller)
        #expect(controller.handle(.runEnded) == [.startRun("Late")])
        #expect(controller.state.running)
        #expect(controller.handle(.runEnded).isEmpty)
        #expect(!controller.state.running)
    }

    @Test func `an acknowledged message is not restarted by runEnded`() {
        var controller = ScreenController(label: "m", options: .legacy)
        _ = submit("Start", to: &controller)
        _ = submit("Once", to: &controller)
        controller.handle(.promptAccepted(id: 0, text: "Once"))
        #expect(controller.handle(.runEnded).isEmpty)
        #expect(!controller.state.running)
    }

    @Test func `a restarted run receives the other queued messages and steering wins`() {
        var controller = ScreenController(label: "m", options: .legacy)
        _ = submit("Start", to: &controller)
        _ = submit("Later", to: &controller, followUp: true)
        _ = submit("First", to: &controller)
        #expect(
            controller.handle(.runEnded) == [
                .startRun("First"), .queuePrompt(id: 0, text: "Later", followUp: true)
            ])
    }

    @Test func `abort returns unsent messages and the unfinished draft without restarting`() {
        var controller = ScreenController(label: "m", options: .legacy)
        _ = submit("Start", to: &controller)
        _ = submit("One", to: &controller)
        _ = submit("Two", to: &controller, followUp: true)
        _ = controller.handle(.key(KeyEvent(keyCode: 0x03)), pageRows: 10)
        _ = controller.handle(.paste("draft"), pageRows: 10)
        #expect(controller.handle(.runEnded).isEmpty)
        #expect(controller.state.editor.text == "One\n\nTwo\n\ndraft")
        #expect(!controller.state.running)
    }

    @Test func `failure returns only messages that were not acknowledged`() {
        var controller = ScreenController(label: "m", options: .legacy)
        _ = submit("Start", to: &controller)
        _ = submit("Recorded", to: &controller)
        _ = submit("Unsent", to: &controller)
        controller.handle(.promptAccepted(id: 0, text: "Recorded"))
        controller.handle(.returnQueuedPrompts)
        #expect(controller.handle(.runEnded).isEmpty)
        #expect(controller.state.editor.text == "Unsent")
    }

    @Test func `input typed during abort stays local and a late acknowledgment removes only its own message`() {
        var controller = ScreenController(label: "m", options: .legacy)
        _ = submit("Start", to: &controller)
        _ = submit("Recorded", to: &controller)
        _ = controller.handle(.key(KeyEvent(keyCode: 0x03)), pageRows: 10)
        #expect(submit("During abort", to: &controller).isEmpty)
        controller.handle(.promptAccepted(id: 0, text: "Recorded"))
        #expect(controller.handle(.runEnded).isEmpty)
        #expect(controller.state.editor.text == "During abort")
    }

    @Test(arguments: [false, true])
    func `the follow-up command works without a modified Enter key`(busy: Bool) {
        var controller = ScreenController(label: "m", options: .legacy)
        if busy { _ = submit("Start", to: &controller) }
        let effect = submit("/follow-up Later", to: &controller)
        #expect(effect == (busy ? [.queuePrompt(id: 0, text: "Later", followUp: true)] : [.startRun("Later")]))
    }

    @Test func `an empty follow-up command never starts a model request`() {
        var controller = ScreenController(label: "m", options: .legacy)
        #expect(submit("/follow-up", to: &controller).isEmpty)
        #expect(!controller.state.running)
    }

    @Test func `typing during a command is returned to the editor rather than lost or steered`() {
        var controller = ScreenController(
            label: "m", commands: [SlashCommand(name: "config", summary: "Settings")], options: .legacy)
        _ = submit("/config", to: &controller)
        #expect(submit("Keep me", to: &controller).isEmpty)
        #expect(controller.state.editor.text == "Keep me")
        #expect(controller.handle(.runEnded).isEmpty)
    }
}
