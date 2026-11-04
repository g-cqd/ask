import TerminalKitRender
import TerminalKitStyle
import Testing

@testable import AskTUI

/// The sidebar's sections (roadmap 0194): threads as a tree under the main conversation, then the jobs, one row each; and a tinted
/// block's background stops at the divider.
@Suite("The sidebar has a tree of threads and a list of jobs, and no block's colour reaches it")
struct SidebarSectionsTests {
    private static let runners = [
        RunnerInfo(name: "[#26a7]", detail: "swift build", id: "job-1"),
        RunnerInfo(name: "[#078c]", detail: "npm test", id: "job-2", state: .done),
        RunnerInfo(name: "thread-1", detail: "look into X", id: "thread-1", kind: .agent),
        RunnerInfo(name: "#9f00", detail: "make", id: "job-3", parentID: "thread-1"),
        RunnerInfo(
            name: "thread-3",
            detail: "deeper",
            id: "thread-3",
            parentID: "thread-1",
            kind: .agent,
            state: .failed
        ),
        RunnerInfo(name: "thread-2", detail: "check pins", id: "thread-2", kind: .agent, state: .done)
    ]

    private func rig(updates: [ConversationUpdate] = []) -> PointerRig {
        var rig = PointerRig(
            columns: 100,
            rows: 24,
            options: ScreenOptions(sidebar: true, prompt: "ask> "),
            updates: updates
        )
        rig.controller.handle(.runners(Self.runners))
        rig.draw()
        return rig
    }

    private func panel(_ rig: PointerRig, row: Int) -> String {
        var text = Substring(rig.text(row: row).dropFirst(rig.controller.frame.transcriptColumns + 2))
        while text.last == " " { text.removeLast() }
        return String(text)
    }

    @Test func `threads come first, as a tree under main with a thread's jobs beneath it, then the jobs`() {
        let rig = rig()
        let rows = (0 ..< 11).map { panel(rig, row: $0) }
        #expect(
            rows[0].hasSuffix(Sidebar.closeMark) && rows[0].allSatisfy { $0 == " " || String($0) == Sidebar.closeMark }
        )
        #expect(rows[1] == "◆ main")
        #expect(rows[2].hasPrefix("├ ") && rows[2].contains("thread-1 look into X"))
        #expect(rows[3].hasPrefix("│ ├ ") && rows[3].contains("9f00 make"), "a job thread-1 started stays under it")
        #expect(rows[4] == "│ └ ✗ thread-3 deeper")
        #expect(rows[5] == "└ ✓ thread-2 check pins")
        #expect(rows[6].isEmpty)
        #expect(rows[7] == "Jobs")
        #expect(rows[8].contains("#26a7 swift build") && !rows[8].contains("["), "a job is named without brackets")
        #expect(rows[9] == "✓ #078c npm test")
        #expect(
            rig.controller.frame.sidebarIDs.prefix(10)
                == [
                    Sidebar.toggleID, RunnerStrip.mainID, "thread-1", "job-3", "thread-3", "thread-2", "", "", "job-1",
                    "job-2"
                ]
        )
        #expect(
            panel(rig, row: rig.composer.transcriptRows - 1) == "1 thread, 2 jobs running",
            "the counts, at the bottom"
        )
    }

    @Test func `the keys move through the rows in the order they are drawn`() {
        let order = rig().controller.state.runnerTree.rows.map(\.runner.id)
        #expect(order == ["thread-1", "job-3", "thread-3", "thread-2", "job-1", "job-2"])
    }

    @Test func `a click on main goes back from a lane, and the lane shown is bold`() {
        var rig = rig()
        let column = rig.controller.frame.transcriptColumns + 4
        _ = rig.click(row: 9, col: column)
        #expect(rig.controller.state.lane?.id == "job-2")
        rig.draw()
        #expect(rig.buffer[9, column].style.bold && !rig.buffer[1, column].style.bold)
        _ = rig.click(row: 1, col: column)
        #expect(rig.controller.state.lane == nil)
    }

    @Test func `a tinted block's background stops at the divider`() {
        let rig = rig(updates: [.userPrompt("hello"), .toolStarted(name: "bash", summary: "ls", id: "t")])
        let divider = rig.controller.frame.transcriptColumns
        var tinted = 0
        for row in 0 ..< rig.composer.transcriptRows {
            if rig.buffer[row, divider - 1].style.bg != .default { tinted += 1 }
            for column in divider ..< 100 {
                #expect(rig.buffer[row, column].style.bg == .default, "row \(row), column \(column)")
            }
        }
        #expect(tinted > 0, "some block is tinted, so the check means something")
    }
}
