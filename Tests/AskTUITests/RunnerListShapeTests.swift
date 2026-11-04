import TerminalKitCodecs
import TerminalKitInput
import Testing

@testable import AskTUI

/// The list under the input (the owner, 2026-11-04): flat while there are only jobs, the sidebar's tree once a thread exists; and never
/// beside the sidebar, which is then the list.
@Suite("The list under the input is flat for jobs, a tree with threads, and only shown without the sidebar")
struct RunnerListShapeTests {
    private func state(_ runners: [RunnerInfo], sidebar: Bool = false) -> ScreenState {
        var state = ScreenState(label: "m", options: .legacy)
        state.runners = runners
        state.runnersOpen = true
        state.sidebarOpen = sidebar
        return state
    }

    @Test func `with only jobs it is a flat list`() {
        let rows = ScreenComposer.runnerRows(
            for: state([RunnerInfo(name: "job-1", detail: "sleep"), RunnerInfo(name: "job-2", detail: "make")]),
            available: 10,
            columns: 100
        )
        #expect(rows.map(\.text) == ["job-1  sleep · running", "job-2  make · running"])
    }

    @Test func `with a thread it is the tree, and the jobs follow without an empty row`() {
        let rows = ScreenComposer.runnerRows(
            for: state([
                RunnerInfo(name: "thread-1", detail: "look", kind: .agent), RunnerInfo(name: "job-1", detail: "sleep")
            ]),
            available: 10,
            columns: 100
        )
        #expect(rows.map(\.text) == ["◆ main", "└ ● thread-1 look", "Jobs", "● job-1 sleep"])
    }

    @Test func `beside a shown sidebar it is not drawn; on a screen too narrow for the sidebar it is`() {
        let open = state([RunnerInfo(name: "job-1", detail: "sleep")], sidebar: true)
        #expect(ScreenComposer.runnerRows(for: open, available: 10, columns: 100).isEmpty)
        #expect(
            !ScreenComposer.runnerRows(for: open, available: 10, columns: 60).isEmpty,
            "60 columns cannot show the sidebar"
        )
    }

    /// Note n22: below the input, merged threads are left out; `/threads` reaches them.
    @Test func `merged threads are left out of the list under the input`() {
        let rows = ScreenComposer.runnerRows(
            for: state([
                RunnerInfo(name: "thread-1", detail: "done", kind: .agent, state: .merged),
                RunnerInfo(name: "thread-2", detail: "look", kind: .agent),
                RunnerInfo(name: "job-1", detail: "sleep")
            ]),
            available: 10,
            columns: 100
        )
        #expect(rows.map(\.text) == ["◆ main", "└ ● thread-2 look", "Jobs", "● job-1 sleep"])
    }

    @Test func `with only merged threads left it is the flat list of jobs`() {
        let rows = ScreenComposer.runnerRows(
            for: state([
                RunnerInfo(name: "thread-1", detail: "done", kind: .agent, state: .merged),
                RunnerInfo(name: "job-1", detail: "sleep")
            ]),
            available: 10,
            columns: 100
        )
        #expect(rows.map(\.text) == ["job-1  sleep · running"])
    }

    @Test func `the keys skip what the list leaves out`() {
        var controller = ScreenController(label: "m", options: .legacy)
        controller.setScreenRows(30)
        _ = controller.handle(
            .runners([
                RunnerInfo(name: "thread-1", detail: "done", kind: .agent, state: .merged),
                RunnerInfo(name: "thread-2", detail: "look", kind: .agent)
            ])
        )
        controller.state.runnersOpen = true
        _ = controller.handle(.key(KeyEvent(keyCode: Key.down.rawValue)), pageRows: 30)
        #expect(controller.state.stripSelection == "thread-2")
    }
}
