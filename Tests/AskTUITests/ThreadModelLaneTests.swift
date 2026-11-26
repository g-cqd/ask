import TerminalKitCodecs
import TerminalKitInput
import Testing

@testable import AskTUI

/// Owner, 2026-11-26: `/model` in a thread's lane is the thread's, and its lane's status line names the model that answers there,
/// while main's keeps its own.
@Suite("A thread's lane chooses and names its own model")
struct ThreadModelLaneTests {
    private let thread = RunnerInfo(name: "thread-1", detail: "look", id: "thread-1", kind: .agent)

    private func controller() -> ScreenController {
        var controller = ScreenController(label: "main-model", options: .legacy)
        controller.setScreenRows(30)
        _ = controller.handle(.runners([thread]))
        return controller
    }

    @Test func `/model in a thread's lane goes to the thread`() {
        var controller = controller()
        _ = controller.enterLane(thread)
        _ = controller.handle(.paste("/model fast-model"), pageRows: 30)
        let effects = controller.handle(.key(KeyEvent(keyCode: Key.enter.rawValue)), pageRows: 30)
        #expect(effects == [.threadModel(id: "thread-1", arguments: "fast-model")])
        #expect(controller.state.lane?.id == "thread-1", "the lane stays")
    }

    @Test func `the thread's model is named in its lane, and main's outside it`() {
        var controller = controller()
        _ = controller.handle(.thread(id: "thread-1", .label("fast-model")))
        #expect(controller.state.label == "main-model")
        let main = ScreenComposer.segments(for: controller.state, input: "").flatMap(\.forms)
        #expect(main.contains("main-model") && !main.contains("fast-model"))
        _ = controller.enterLane(thread)
        let lane = ScreenComposer.segments(for: controller.state, input: "").flatMap(\.forms)
        #expect(lane.contains("fast-model") && !lane.contains("main-model"))
    }
}
