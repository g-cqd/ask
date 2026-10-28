import TerminalKitText
import Testing

@testable import AskTUI

@Suite("Background jobs animate independently of model turns")
struct RunnerProgressTests {
    @Test func `a running job keeps progress alive without a model turn`() {
        var controller = ScreenController(label: "test")
        controller.handle(.runners([RunnerInfo(name: "job-1", detail: "build")]))
        #expect(!controller.state.running)
        #expect(controller.hasLiveProgress)
        controller.handle(.runners([]))
        #expect(!controller.hasLiveProgress)
    }

    @Test func `a running job ends its strip row with a changing single cell spinner`() {
        var controller = ScreenController(label: "test", options: ScreenOptions(spinner: .line))
        controller.handle(.runners([RunnerInfo(name: "job-1", detail: "build")]))
        controller.state.runnersOpen = true
        let first = RunnerStrip(controller.state, available: 5, columns: 40).lines[0].text
        controller.advanceProgress()
        let second = RunnerStrip(controller.state, available: 5, columns: 40).lines[0].text
        #expect(first != second)
        #expect(UnicodeWidth.displayWidth(of: String(first.suffix(1))) == 1)
        #expect(SpinnerStyle.line.frames.contains(String(first.suffix(1))))
        #expect(UnicodeWidth.displayWidth(of: first) == 40)
    }

    @Test func `terminal runners never keep the progress timer alive`() {
        var controller = ScreenController(label: "test")
        controller.handle(.runners([RunnerInfo(name: "job-1", detail: "build", state: .done)]))
        #expect(!controller.hasLiveProgress)
    }

    @Test func `job elapsed time starts at launch and survives snapshots and focusing`() {
        let start = ContinuousClock.now
        var controller = ScreenController(label: "test", options: ScreenOptions(localizedDurations: false))
        let runner = RunnerInfo(name: "job-1", detail: "build", startedAt: start)
        controller.setRunners([runner], at: start + .seconds(61))
        controller.state.runnersOpen = true
        #expect(RunnerStrip(controller.state, available: 5, columns: 40).lines[0].text.hasSuffix("1:01 · |"))
        _ = controller.enterLane(runner)
        controller.advanceProgress(at: start + .seconds(62))
        controller.setRunners([runner], at: start + .seconds(63))
        #expect(controller.state.runnerProgress[runner.id]?.started == start)
        #expect(RunnerStrip(controller.state, available: 5, columns: 40).lines[0].text.hasSuffix("1:03 · /"))
        controller.leaveLane()
        #expect(controller.state.runnerProgress[runner.id]?.started == start)
    }

    @Test func `metadata stays inside every narrow width with wide and combining commands`() {
        let start = ContinuousClock.now
        var controller = ScreenController(label: "test", options: ScreenOptions(localizedDurations: false))
        controller.setRunners(
            [
                RunnerInfo(name: "job-1", detail: String(repeating: "界é", count: 40), startedAt: start)
            ], at: start + .seconds(3661))
        controller.state.runnersOpen = true
        for columns in 1 ... 80 {
            let text = RunnerStrip(controller.state, available: 5, columns: columns).lines[0].text
            #expect(UnicodeWidth.displayWidth(of: text) == columns)
            #expect(text.hasSuffix("|"))
        }
        let text = RunnerStrip(controller.state, available: 5, columns: 80).lines[0].text
        #expect(
            text.hasSuffix("…    1:01:01 · |"),
            "a cut command ends with an ellipsis, four cells before the time (roadmap 0100)")
    }

    @Test func `a row with no clock that is too wide ends with an ellipsis at the edge`() {
        var controller = ScreenController(label: "test")
        controller.setRunners(
            [RunnerInfo(name: "job-1", detail: String(repeating: "x", count: 100), state: .done)], at: .now)
        controller.state.runnersOpen = true
        for columns in [10, 33, 60] {
            let text = RunnerStrip(controller.state, available: 5, columns: columns).lines[0].text
            #expect(UnicodeWidth.displayWidth(of: text) == columns && text.hasSuffix("…"), "\(columns): \(text)")
        }
        let wide = RunnerStrip(controller.state, available: 5, columns: 200).lines[0].text
        #expect(!wide.contains("…"), "a row that fits is not cut")
    }

    @Test func `terminal and removed jobs discard clocks without stopping a live model`() {
        let start = ContinuousClock.now
        var controller = ScreenController(label: "test")
        controller.setRunners([RunnerInfo(name: "job-1", detail: "build")], at: start)
        controller.setRunners([RunnerInfo(name: "job-1", detail: "build", state: .done)], at: start)
        #expect(controller.state.runnerProgress.isEmpty)
        controller.state.running = true
        controller.setRunners([], at: start)
        #expect(controller.hasLiveProgress)
    }

    @Test func `ruled and plain tiny screens bound strip rows and preserve input`() {
        for separator in [false, true] {
            for rows in 1 ... 16 {
                var rig = PointerRig(columns: 20, rows: rows, options: ScreenOptions(separator: separator))
                rig.controller.handle(.runners((0 ..< 9).map { RunnerInfo(name: "job-\($0)", detail: "work") }))
                rig.controller.state.runnersOpen = true
                rig.draw()
                let frame = rig.controller.frame
                #expect(frame.promptRow >= 0 && frame.promptRow < rows)
                #expect(frame.transcriptRows >= 0)
                if !frame.stripIDs.isEmpty {
                    #expect(frame.stripFirstRow == frame.statusRow + 2)
                    #expect(frame.stripFirstRow + frame.stripIDs.count <= rows)
                }
            }
        }
    }

    @Test func `the strip has a blank unclickable row after status`() {
        var rig = PointerRig(columns: 60, rows: 14)
        rig.controller.handle(.runners([RunnerInfo(name: "job-1", detail: "build")]))
        rig.controller.state.runnersOpen = true
        rig.draw()
        let frame = rig.controller.frame
        #expect(frame.stripFirstRow == frame.statusRow + 2)
        #expect(rig.text(row: frame.statusRow + 1).isEmpty)
        #expect(rig.click(row: frame.statusRow + 1, col: 0).isEmpty)
        #expect(rig.controller.state.lane == nil)
        #expect(rig.click(row: frame.stripFirstRow, col: 0) == [.readRunnerOutput(id: "job-1")])
    }
}
