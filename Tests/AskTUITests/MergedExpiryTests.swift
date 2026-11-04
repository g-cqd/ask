import Testing

@testable import AskTUI

/// `threads.mergedShownFor` (note n22): a merged thread stays in the sidebar for a while, then leaves it; `/threads` still reaches it.
@Suite("A merged thread leaves the sidebar once it has been merged long enough")
struct MergedExpiryTests {
    private let merged = RunnerInfo(name: "thread-1", detail: "done", id: "thread-1", kind: .agent, state: .merged)
    private let working = RunnerInfo(name: "thread-2", detail: "look", id: "thread-2", kind: .agent)

    private func controller(shownFor: Duration?) -> ScreenController {
        var options = ScreenOptions.legacy
        options.sidebar = true
        options.mergedShownFor = shownFor
        var controller = ScreenController(label: "m", options: options)
        controller.setScreenRows(30)
        return controller
    }

    private func sidebarNames(_ controller: ScreenController) -> [String] {
        SidebarEntries(controller.state, columns: 30).entries.map(\.id).filter { $0.hasPrefix("thread-") }
    }

    @Test func `it is listed until it has been merged for the setting, then not`() {
        var controller = controller(shownFor: .seconds(60))
        let start = ContinuousClock.now
        controller.setRunners([merged, working], at: start)
        #expect(sidebarNames(controller) == ["thread-1", "thread-2"])
        controller.setRunners([merged, working], at: start + .seconds(59))
        #expect(sidebarNames(controller) == ["thread-1", "thread-2"], "within the minute")
        controller.advanceProgress(at: start + .seconds(61))
        #expect(sidebarNames(controller) == ["thread-2"], "past it, even without a new list")
    }

    @Test func `always keeps it`() {
        var controller = controller(shownFor: nil)
        let start = ContinuousClock.now
        controller.setRunners([merged], at: start)
        controller.advanceProgress(at: start + .seconds(365 * 86_400))
        #expect(sidebarNames(controller) == ["thread-1"])
    }
}
