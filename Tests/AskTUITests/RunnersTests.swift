internal import TerminalKitCodecs
internal import TerminalKitInput
internal import TerminalKitRender
internal import Testing

@testable import AskTUI

/// What runs beside the conversation: counted in the status line, listed by a click on the count or by /tasks.
@Suite("The status line counts the running jobs, and the count opens their list")
struct RunnersTests {
    private static let two = [
        RunnerInfo(name: "job-1", detail: "npm run dev"), RunnerInfo(name: "job-2", detail: "tail -f log\nsecond line")
    ]
    /// Fourteen rows: opening the strip moves the status and prompt up, and the runners sit below the input.
    private func rig(_ options: ScreenOptions = ScreenOptions()) -> PointerRig {
        var rig = PointerRig(columns: 40, rows: 14, options: options, lines: ["one", "two"])
        rig.controller.handle(.runners(Self.two))
        rig.draw()
        return rig
    }

    @Test func `the count is in the status line after the activity`() {
        let rig = rig()
        #expect(rig.text(row: 12) == "m · 2 jobs")
        #expect(rig.text(row: 11) == "two", "no list is open: the transcript owns the rows above the status line")
        var one = PointerRig(columns: 40, rows: 14)
        one.controller.handle(.runners([Self.two[0]]))
        one.draw()
        #expect(one.text(row: 12) == "m · 1 job")
    }

    @Test func `a click on the count opens the strip below the input, and the moved count closes it`() {
        var rig = rig()
        rig.click(row: 12, col: 5)
        #expect(rig.text(row: 12) == "job-1  npm run dev · running")
        #expect(rig.text(row: 13) == "job-2  tail -f log second line · running")
        #expect(rig.text(row: 10) == "m · 2 jobs")
        #expect(rig.text(row: 11) == "ask>")
        #expect(rig.buffer[12, 0].style.dim)
        rig.click(row: 10, col: 5)
        #expect(rig.text(row: 10) == "one" && rig.text(row: 11) == "two")
        #expect(rig.text(row: 12) == "m · 2 jobs")
    }

    @Test func `a click elsewhere on the status line does nothing`() {
        var rig = rig()
        for column in [0, 1, 2, 3, 10, 18, 30, 39] {
            rig.click(row: 12, col: column)
            #expect(!rig.controller.state.runnersOpen, "column \(column)")
        }
        for column in [4, 6, 9] {
            rig.click(row: 12, col: column)
            #expect(rig.controller.state.runnersOpen, "column \(column)")
            rig.click(row: 10, col: column)
        }
    }

    @Test func `clicks in quick succession each toggle, however the recognizer counts them`() {
        var rig = rig()
        let quick = Duration.milliseconds(50)
        rig.click(row: 12, col: 5, after: quick)
        #expect(rig.controller.state.runnersOpen)
        rig.click(row: 10, col: 5, after: quick)
        #expect(!rig.controller.state.runnersOpen)
        rig.click(row: 12, col: 5, after: quick)
        #expect(rig.controller.state.runnersOpen, "the third click of a triple is still a toggle")
    }

    @Test func `the list takes rows from the transcript and gives them back`() {
        var rig = rig()
        let before = rig.composer.transcriptRows
        rig.click(row: 12, col: 5)
        #expect(rig.composer.transcriptRows == before - 2)
        rig.click(row: 10, col: 5)
        #expect(rig.composer.transcriptRows == before)
    }

    @Test func `a click on the count after the list moved the status row still lands on it`() {
        var rig = rig()
        rig.click(row: 12, col: 5)
        rig.click(row: 10, col: 5)
        #expect(!rig.controller.state.runnersOpen)
    }

    @Test func `slash tasks does the same, with the mouse off too, and says when nothing is running`() {
        var rig = rig(ScreenOptions(mouse: false))
        for character in "/tasks" {
            _ = rig.controller.handle(.key(KeyEvent(keyCode: UInt32(character.asciiValue!))), pageRows: 10)
        }
        _ = rig.controller.handle(.key(KeyEvent(keyCode: 0x0D)), pageRows: 10)
        rig.draw()
        #expect(rig.controller.state.runnersOpen && rig.text(row: 13).hasPrefix("job-2"))
        var empty = PointerRig(columns: 40, rows: 14)
        for character in "/tasks" {
            _ = empty.controller.handle(.key(KeyEvent(keyCode: UInt32(character.asciiValue!))), pageRows: 10)
        }
        _ = empty.controller.handle(.key(KeyEvent(keyCode: 0x0D)), pageRows: 10)
        #expect(
            empty.controller.state.transcript.items.last == .notice("No background jobs are running.", isError: false))
    }

    @Test func `the list closes by itself when nothing is running`() {
        var rig = rig()
        rig.click(row: 12, col: 5)
        rig.controller.handle(.runners([]))
        rig.draw()
        #expect(!rig.controller.state.runnersOpen)
        #expect(rig.text(row: 12) == "m" && rig.text(row: 11) == "two")
        rig.controller.handle(.runners(Self.two))
        rig.draw()
        #expect(rig.text(row: 11) == "two", "a list that closed stays closed when jobs come back")
    }

    @Test func `more than five say how many are not shown`() {
        var rig = rig()
        rig.controller.handle(.runners((1 ... 8).map { RunnerInfo(name: "job-\($0)", detail: "sleep \($0)") }))
        rig.controller.state.runnersOpen = true
        rig.draw()
        #expect(
            (9 ... 12).map { rig.text(row: $0) } == [
                "job-1  sleep 1 · running", "job-2  sleep 2 · running", "job-3  sleep 3 · running",
                "job-4  sleep 4 · running"
            ])
        #expect(rig.text(row: 13) == "… 4 more")
        #expect(rig.text(row: 7) == "m · 8 jobs")
    }

    @Test func `a tiny screen has no room for the list and nothing breaks`() {
        for rows in 1 ... 4 {
            var rig = PointerRig(columns: 20, rows: rows)
            rig.controller.handle(.runners(Self.two))
            rig.controller.state.runnersOpen = true
            rig.draw()
            #expect(rig.composer.transcriptRows >= 0)
            rig.mouse(.left, .press, row: 0, col: 0)
            rig.mouse(.left, .release, row: 0, col: 0)
        }
    }

    @Test func `the list is not content: a drag across it selects nothing and the transcript still selects`() {
        var rig = rig()
        rig.click(row: 12, col: 5)
        #expect(rig.drag(from: (12, 0), to: (13, 10)).isEmpty)
        #expect(rig.controller.state.selection == nil)
        #expect(
            rig.drag(from: (rig.composer.transcriptRows - 1, 0), to: (rig.composer.transcriptRows - 1, 2)) == [
                .copy("two"[...].prefix(3).description)
            ])
    }
}
