import Testing

@testable import AskTUI

/// The sidebar's marks for running runners (roadmap 0195, note n15): the spinner while one works, and once it has been quiet for three
/// seconds, its kind: `◇` a thread, `$` a job. A thread's activity is its events; a job's is its output, which its owner reports.
@Suite("A running runner spins while it works, and shows its kind once quiet")
struct RunnerMarksTests {
    private let thread = RunnerInfo(name: "thread-1", detail: "look", id: "thread-1", kind: .agent)
    private let job = RunnerInfo(name: "[#1]", detail: "sleep 30", id: "job-1", parentID: nil, kind: .job)

    private func controller() -> ScreenController {
        var options = ScreenOptions.legacy
        options.sidebar = true
        var controller = ScreenController(label: "m", options: options)
        controller.setScreenRows(30)
        return controller
    }

    /// The mark of runner `id`'s row: its first character after the tree guide.
    private func mark(_ controller: ScreenController, _ id: String) -> String? {
        guard let entry = SidebarEntries(controller.state, columns: 40).entries.first(where: { $0.id == id }) else {
            return nil
        }
        return entry.text.drop { "│├└─ ".contains($0) }.first.map(String.init)
    }

    private func spins(_ mark: String?) -> Bool { mark.map { SpinnerStyle.line.frames.contains($0) } ?? false }

    @Test func `a job spins at first, and shows $ once it has said nothing for three seconds`() {
        var controller = controller()
        let start = ContinuousClock.now
        controller.setRunners([job], at: start)
        controller.advanceProgress(at: start + .seconds(1))
        #expect(spins(mark(controller, "job-1")))
        controller.advanceProgress(at: start + .seconds(4))
        #expect(mark(controller, "job-1") == "$")
    }

    @Test func `its output, reported by its owner, makes it spin again`() {
        var controller = controller()
        let start = ContinuousClock.now
        controller.setRunners([job], at: start)
        _ = controller.handle(.runnerActivity(["job-1": start + .seconds(5)]))
        controller.advanceProgress(at: start + .seconds(6))
        #expect(spins(mark(controller, "job-1")))
        controller.advanceProgress(at: start + .seconds(9))
        #expect(mark(controller, "job-1") == "$")
    }

    @Test func `a quiet thread shows ◇, and its events make it spin`() {
        var controller = controller()
        let start = ContinuousClock.now - .seconds(10)
        controller.setRunners([thread], at: start)
        controller.advanceProgress(at: .now)
        #expect(mark(controller, "thread-1") == "◇")
        _ = controller.handle(.thread(id: "thread-1", .assistantText("working on it")))
        controller.advanceProgress(at: .now)
        #expect(spins(mark(controller, "thread-1")))
    }

    @Test func `ended and waiting runners keep their marks`() {
        var controller = controller()
        let start = ContinuousClock.now
        var stopped = thread
        stopped.state = .stopped
        var asking = job
        asking.state = .waitingForApproval
        controller.setRunners([stopped, asking], at: start)
        controller.advanceProgress(at: start + .seconds(10))
        #expect(mark(controller, "thread-1") == "■" && mark(controller, "job-1") == "?")
    }
}
