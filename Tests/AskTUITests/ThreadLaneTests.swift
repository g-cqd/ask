import TerminalKitCodecs
import TerminalKitInput
import Testing

@testable import AskTUI

/// Threads (roadmap 0194): each thread's updates fill its own conversation, never main's; its lane shows that conversation live, and
/// what is typed there goes to the thread, while a command still goes back to main.
@Suite("A thread has a conversation of its own, and its lane talks to it")
struct ThreadLaneTests {
    private let runner = RunnerInfo(name: "thread-1", detail: "look into X", id: "thread-1", kind: .agent)

    private func controller() -> ScreenController {
        var controller = ScreenController(
            label: "m",
            commands: [SlashCommand(name: "tasks", summary: "t")],
            options: .legacy
        )
        controller.setScreenRows(30)
        _ = controller.handle(.runners([runner]))
        return controller
    }

    private func texts(_ transcript: Transcript) -> [String] {
        transcript.items.compactMap { item in
            switch item {
                case .assistant(let text), .user(let text): text
                default: nil
            }
        }
    }

    private func type(_ text: String, _ controller: inout ScreenController) -> [ScreenController.Effect] {
        for scalar in text.unicodeScalars { _ = controller.handle(.key(KeyEvent(keyCode: scalar.value)), pageRows: 30) }
        return controller.handle(.key(KeyEvent(keyCode: Key.enter.rawValue)), pageRows: 30)
    }

    @Test func `a thread's updates fill its own conversation and leave main's alone`() {
        var controller = controller()
        let main = controller.state.transcript.items.count
        _ = controller.handle(.thread(id: "thread-1", .userPrompt("look into X")))
        _ = controller.handle(.thread(id: "thread-1", .assistantText("found it")))
        _ = controller.handle(.thread(id: "thread-1", .runEnded))
        #expect(controller.state.transcript.items.count == main)
        #expect(texts(controller.state.threads["thread-1"] ?? Transcript()) == ["look into X", "found it"])
        #expect(!controller.state.running, "a thread's end is not main's")
    }

    @Test func `its lane shows that conversation live, sends what is typed to it, and keeps it when left`() {
        var controller = controller()
        _ = controller.handle(.thread(id: "thread-1", .assistantText("first")))
        _ = controller.enterLane(runner)
        #expect(texts(controller.state.transcript) == ["first"])
        _ = controller.handle(.thread(id: "thread-1", .assistantText(" more")))
        #expect(texts(controller.state.transcript) == ["first more"], "updates reach the lane while it is shown")
        let effects = type("and then?", &controller)
        #expect(effects == [.sendToThread(id: "thread-1", text: "and then?")])
        #expect(controller.state.lane?.id == "thread-1", "a message keeps the lane")
        #expect(texts(controller.state.transcript) == ["first more", "and then?"])
        controller.leaveLane()
        #expect(texts(controller.state.threads["thread-1"] ?? Transcript()) == ["first more", "and then?"])
        #expect(!texts(controller.state.transcript).contains("and then?"), "main never saw it")
    }

    @Test func `a command typed in the lane goes back to main`() {
        var controller = controller()
        _ = controller.enterLane(runner)
        let effects = type("/tasks", &controller)
        #expect(controller.state.lane == nil)
        #expect(effects.contains(.runCommand(name: "tasks", arguments: "")))
    }
}
