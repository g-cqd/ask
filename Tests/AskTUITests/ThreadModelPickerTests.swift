import TerminalKitCodecs
import TerminalKitInput
import Testing

@testable import AskTUI

/// Owner, 2026-11-27: a model chosen from the `/model` list in a thread's lane is the thread's, as a typed one is; and the list is
/// asked for again when the lane changes, so it marks the model that answers where it is opened.
@Suite("The /model list in a thread's lane chooses the thread's model")
struct ThreadModelPickerTests {
    private let thread = RunnerInfo(name: "thread-1", detail: "look", id: "thread-1", kind: .agent)
    private static let models = [
        ChoiceRow(label: "claude-a", arguments: "claude-a"), ChoiceRow(label: "claude-b", arguments: "claude-b")
    ]

    private func screen() -> ScreenController {
        var screen = ScreenController(
            label: "m",
            commands: [SlashCommand(name: "model", summary: "Choose a model.", takesChoices: true)]
        )
        screen.setScreenRows(30)
        _ = screen.handle(.runners([thread]))
        return screen
    }

    private func type(_ text: String, into screen: inout ScreenController) -> [ScreenController.Effect] {
        var effects: [ScreenController.Effect] = []
        for scalar in text.unicodeScalars {
            effects += screen.handle(.key(KeyEvent(keyCode: scalar.value)), pageRows: 30)
        }
        return effects.filter { $0 != .listSkills }
    }

    @Test func `a row chosen in a thread's lane goes to the thread, and the lane stays`() {
        var screen = screen()
        _ = screen.enterLane(thread)
        _ = screen.handle(.choices(command: "model", rows: Self.models))
        _ = type("/model claude-b", into: &screen)
        #expect(type("\r", into: &screen) == [.threadModel(id: "thread-1", arguments: "claude-b")])
        #expect(screen.state.lane?.id == "thread-1")
    }

    @Test func `in main the same row is main's`() {
        var screen = screen()
        _ = screen.handle(.choices(command: "model", rows: Self.models))
        _ = type("/model claude-b", into: &screen)
        #expect(type("\r", into: &screen) == [.runCommand(name: "model", arguments: "claude-b")])
    }

    @Test func `entering or leaving a lane, or the thread's model changing, asks for the list again`() {
        var screen = screen()
        _ = screen.handle(.choices(command: "model", rows: Self.models))
        _ = screen.enterLane(thread)
        #expect(screen.state.choices["model"] == nil)
        _ = screen.handle(.choices(command: "model", rows: Self.models))
        _ = screen.handle(.thread(id: "thread-1", .label("claude-b")))
        #expect(screen.state.choices["model"] == nil)
        _ = screen.handle(.choices(command: "model", rows: Self.models))
        screen.leaveLane()
        #expect(screen.state.choices["model"] == nil)
    }
}
