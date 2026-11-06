import TerminalKitCodecs
import TerminalKitInput
import Testing

@testable import AskTUI

/// Where the sidebar lists a thread's jobs (roadmap 0195, `ui.sidebarJobs`): under the thread by default, or with every job in the
/// Jobs section; `/sidebar jobs` switches it, and the keys follow the order drawn either way.
@Suite("A thread's jobs are listed under it, or in the Jobs section")
struct SidebarJobsTests {
    private static let runners = [
        RunnerInfo(name: "thread-1", detail: "look", id: "thread-1", kind: .agent),
        RunnerInfo(name: "[#1a2b]", detail: "swift build", id: "job-1", parentID: "thread-1"),
        RunnerInfo(name: "[#3c4d]", detail: "npm test", id: "job-2")
    ]

    private func rig(inTree: Bool = true) -> PointerRig {
        var rig = PointerRig(
            columns: 100,
            rows: 24,
            options: ScreenOptions(sidebar: true, sidebarLayout: .full, sidebarJobsInTree: inTree, prompt: "ask> ")
        )
        rig.controller.handle(.runners(Self.runners))
        rig.draw()
        return rig
    }

    private func panel(_ rig: PointerRig) -> [String] {
        (0 ..< 9)
            .map { row in
                var text = Substring(rig.text(row: row).dropFirst(rig.controller.frame.transcriptColumns + 2))
                while text.last == " " { text.removeLast() }
                return String(text)
            }
    }

    @Test func `by default a thread's job is under the thread`() {
        let rows = panel(rig())
        #expect(rows[2].hasPrefix("└ ") && rows[2].contains("thread-1"))
        #expect(rows[3].hasPrefix("  └ ") && rows[3].contains("#1a2b swift build"))
        #expect(
            rows[5] == "Jobs" && rows[6].contains("#3c4d npm test")
                && !rows.contains { $0.hasSuffix("#1a2b swift build") && $0.hasPrefix("●") }
        )
    }

    @Test func `as a section, every job is in the Jobs section, and the keys follow that order`() {
        let rig = rig(inTree: false)
        let rows = panel(rig)
        #expect(rows[2].contains("thread-1") && !rows[3].contains("swift build"))
        #expect(
            rows.contains("Jobs") && rows.contains { $0.contains("#1a2b swift build") }
                && rows.contains { $0.contains("#3c4d npm test") }
        )
        #expect(rig.controller.state.runnerTree.rows.map(\.runner.id) == ["thread-1", "job-1", "job-2"])
        #expect(rig.controller.state.runnerTree.rows.allSatisfy { $0.depth == 0 })
    }

    /// Said with the sidebar closed, where nothing on screen moves (note n28); open, the jobs moving is the answer.
    @Test func `sidebar jobs switches it for the run, and says so`() {
        var rig = rig()
        rig.controller.state.sidebarOpen = false
        for scalar in "/sidebar jobs".unicodeScalars {
            _ = rig.controller.handle(.key(.init(keyCode: scalar.value)), pageRows: 20)
        }
        _ = rig.controller.handle(.key(.init(keyCode: 0x0D)), pageRows: 20)
        rig.draw()
        #expect(!rig.controller.state.jobsInTree)
        #expect(
            rig.controller.state.transcript.items.contains(
                .notice("Jobs are listed in the Jobs section.", isError: false)
            )
        )
        #expect(rig.controller.state.runnerTree.rows.allSatisfy { $0.depth == 0 })
    }
}
