import Foundation
import TerminalKitCodecs
import TerminalKitInput
import TerminalKitRender
import TerminalKitStyle
import Testing

@testable import AskTUI

/// The runner sidebar, character layout (roadmap 0062, step 4): the strip's tree beside the transcript, behind a divider, only where it fits.
@Suite("The sidebar shows the strip's tree beside the transcript, and the transcript gives up exactly its width")
struct SidebarTests {
    private static let jobs = [
        RunnerInfo(name: "job-1", detail: "npm run dev"), RunnerInfo(name: "job-2", detail: "tail -f log")
    ]
    private static let long = String(repeating: "word ", count: 30)

    private func rig(columns: Int = 100, sidebar: Bool = true, runners: [RunnerInfo] = SidebarTests.jobs) -> PointerRig
    {
        var rig = PointerRig(
            columns: columns, rows: 20,
            options: ScreenOptions(sidebar: sidebar, prompt: "ask> ", tint: false, separator: false, padding: false),
            lines: [Self.long, "short"])
        rig.controller.handle(.runners(runners))
        rig.draw()
        return rig
    }

    @discardableResult
    private func press(_ code: UInt32, _ rig: inout PointerRig) -> [ScreenController.Effect] {
        let effects = rig.controller.handle(.key(KeyEvent(keyCode: code)), pageRows: 15)
        rig.draw()
        return effects
    }

    private func dividerColumn(_ rig: PointerRig) -> Int? {
        (0 ..< rig.buffer.columns).first { rig.buffer[0, $0].character == "│" }
    }

    @Test func `closed by default, with no divider and the whole width for the transcript`() {
        let rig = rig(sidebar: false)
        #expect(
            dividerColumn(rig) == nil && rig.controller.frame.transcriptColumns == 100
                && rig.controller.frame.sidebarIDs.isEmpty)
    }

    @Test
    func `open, it lists the runners at the top right behind a divider and the transcript is wrapped to what is left`()
    {
        let rig = rig()
        let divider = 100 - 25 - 1
        #expect(dividerColumn(rig) == divider && rig.controller.frame.transcriptColumns == divider)
        #expect(rig.text(row: 0).contains("│ job-1  npm run dev ·"))
        #expect(rig.text(row: 1).contains("│ job-2  tail -f log ·"))
        #expect(rig.controller.frame.sidebarIDs == ["job-1", "job-2"])
        for row in 0 ..< rig.composer.transcriptRows {
            #expect(rig.buffer[row, divider].character == "│", "row \(row)")
        }
        let wrapped = (0 ..< rig.composer.transcriptRows).map { rig.text(row: $0) }.filter { $0.contains("word") }
        #expect(wrapped.count >= 2 && wrapped.allSatisfy { $0.prefix(divider).count <= divider })
    }

    @Test func `the status line, the input and the strip keep the whole width`() {
        var rig = rig()
        rig.controller.state.runnersOpen = true
        rig.controller.state.editor.paste(String(repeating: "x", count: 90))
        rig.draw()
        #expect(rig.text(row: 19 - 2).count > 76 || rig.text(row: 17).count > 76 || rig.text(row: 16).count > 76)
        #expect(rig.buffer[rig.controller.frame.statusRow, 99].character == " " && rig.controller.frame.columns == 100)
    }

    @Test func `with no runners it says so, and it does not take a narrow screen`() {
        let empty = rig(runners: [])
        #expect(empty.text(row: 0).hasSuffix("│ no runners"))
        let narrow = rig(columns: 69)
        #expect(dividerColumn(narrow) == nil && narrow.controller.frame.transcriptColumns == 69)
        let exact = rig(columns: 70)
        #expect(dividerColumn(exact) != nil)
    }

    @Test
    func `Ctrl backslash and the slash command toggle it, and closing gives the width back and clears the divider`() {
        var rig = rig(sidebar: false)
        press(0x1C, &rig)
        #expect(rig.controller.state.sidebarOpen && dividerColumn(rig) != nil)
        press(0x1C, &rig)
        #expect(!rig.controller.state.sidebarOpen && dividerColumn(rig) == nil && !rig.text(row: 0).contains("job-1"))
        for scalar in "/sidebar".unicodeScalars { press(scalar.value, &rig) }
        press(0x0D, &rig)
        #expect(rig.controller.state.sidebarOpen && dividerColumn(rig) != nil)
    }

    @Test func `opening it on a screen that is too narrow says so`() {
        var rig = rig(columns: 60, sidebar: false)
        for scalar in "/sidebar".unicodeScalars { press(scalar.value, &rig) }
        press(0x0D, &rig)
        #expect(
            rig.controller.state.transcript.items.contains(
                .notice("The sidebar needs 70 columns; this screen has 60.", isError: false)))
    }

    @Test func `the strip, the sidebar and the count are one tree: a change shows in all three`() {
        var rig = rig()
        rig.controller.state.runnersOpen = true
        rig.controller.handle(
            .runners(Self.jobs + [RunnerInfo(name: "job-3", detail: "make", state: .waitingForApproval)]))
        rig.draw()
        let all = (0 ..< 20).map { rig.text(row: $0) }.joined(separator: "\n")
        #expect(
            all.components(separatedBy: "job-3  make").count == 3, "the sidebar and the strip")
        #expect(all.contains("3 jobs"))
        rig.controller.handle(.runners([Self.jobs[0]]))
        rig.draw()
        #expect(
            !(0 ..< 20).map { rig.text(row: $0) }.joined().contains("job-3")
                && rig.controller.frame.sidebarIDs == ["job-1"])
    }

    @Test func `Down enters it with the strip closed, the selected row is bold, and Enter focuses that runner`() {
        var rig = rig()
        press(Key.down.rawValue, &rig)
        press(Key.down.rawValue, &rig)
        let start = rig.controller.frame.transcriptColumns + 3
        #expect(rig.buffer[1, start].style.bold && !rig.buffer[0, start].style.bold)
        #expect(press(Key.enter.rawValue, &rig) == [.readRunnerOutput(id: "job-2")])
        #expect(rig.controller.state.lane?.id == "job-2")
    }

    @Test func `a click on a sidebar row focuses it, and a click on the divider or a blank row does nothing`() {
        var rig = rig()
        let column = rig.controller.frame.transcriptColumns + 3
        #expect(rig.click(row: 5, col: column).isEmpty)
        #expect(
            rig.click(row: 0, col: rig.controller.frame.transcriptColumns).isEmpty && rig.controller.state.lane == nil)
        #expect(rig.click(row: 1, col: column) == [.readRunnerOutput(id: "job-2")])
    }

    @Test func `a click in the transcript still selects it, and its columns stop at the divider`() {
        var rig = rig()
        let last = rig.composer.transcriptRows - 1
        rig.drag(from: (last, 0), to: (last, 3))
        #expect(rig.controller.state.selection != nil)
        #expect(rig.inverse(row: last).allSatisfy { $0 < rig.controller.frame.transcriptColumns })
    }

    @Test func `a lane's text and the conversation's both wrap to the width beside the sidebar`() {
        var rig = rig()
        press(Key.down.rawValue, &rig)
        press(Key.enter.rawValue, &rig)
        rig.controller.handle(.runnerOutput(id: "job-1", text: Self.long))
        rig.draw()
        let divider = rig.controller.frame.transcriptColumns
        #expect((0 ..< rig.composer.transcriptRows).allSatisfy { rig.buffer[$0, divider].character == "│" })
        #expect((0 ..< rig.composer.transcriptRows).map { rig.text(row: $0) }.contains { $0.hasPrefix("word word") })
    }
}
