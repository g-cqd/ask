import TerminalKitCodecs
import TerminalKitInput
import Testing

@testable import AskTUI

/// Owner, 2026-11-26: a message sent while the model writes never cuts its reply in two; it shows where the model took it, and where
/// it was queued a gray line says so. One taken before anything came after it stays where it was typed.
@Suite("A queued message never slices a reply, and shows where the model took it")
struct QueuedPlacementTests {
    private func running() -> ScreenController {
        var controller = ScreenController(label: "m", commands: [])
        controller.setScreenRows(30)
        _ = controller.handle(.paste("start"), pageRows: 30)
        _ = controller.handle(.key(KeyEvent(keyCode: Key.enter.rawValue)), pageRows: 30)
        return controller
    }

    private func send(_ text: String, _ controller: inout ScreenController) {
        _ = controller.handle(.paste(text), pageRows: 30)
        _ = controller.handle(.key(KeyEvent(keyCode: Key.enter.rawValue)), pageRows: 30)
    }

    @Test func `the reply goes on in one block above a message queued meanwhile`() {
        var controller = running()
        _ = controller.handle(.assistantText("The first half"))
        send("steer", &controller)
        _ = controller.handle(.assistantText(" and the second half."))
        let items = controller.state.transcript.items
        #expect(items.suffix(2) == [.assistant("The first half and the second half."), .queued("steer")])
    }

    @Test func `taken after more came, it shows at the end, and a gray line stays where it was queued`() {
        var controller = running()
        _ = controller.handle(.assistantText("Working"))
        send("steer", &controller)
        controller.handle(.toolStarted(name: "read", summary: "a.swift", id: "r"))
        controller.handle(.toolFinished(.succeeded, output: "x", id: "r"))
        _ = controller.handle(.promptAccepted(id: 0, text: "steer"))
        let items = controller.state.transcript.items
        #expect(items.last == .user("steer"))
        #expect(items.contains(.notice("Queued here, sent below: steer", isError: false)))
        #expect(!items.contains(.queued("steer")))
    }

    @Test func `taken before anything came after it, it stays where it was typed`() {
        var controller = running()
        _ = controller.handle(.assistantText("Working"))
        send("one", &controller)
        send("two", &controller)
        _ = controller.handle(.promptAccepted(id: 0, text: "one"))
        _ = controller.handle(.promptAccepted(id: 1, text: "two"))
        let items = controller.state.transcript.items
        #expect(items.suffix(3) == [.assistant("Working"), .user("one"), .user("two")])
    }
}
