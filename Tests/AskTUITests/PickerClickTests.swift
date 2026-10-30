internal import TerminalKitCodecs
internal import TerminalKitInput
internal import TerminalKitRender
internal import Testing

@testable import AskTUI

/// A click on a picker row chooses it, as Enter does (roadmap 0048, ADR-0070): the row's text goes into the draft and nothing is
/// sent. Rows are found from what the last frame drew, so a click means what the user saw.
@Suite("A click on a picker row inserts it, and only a row")
struct PickerClickTests {
    /// Twenty rows: the prompt is row 19, the status line row 18, and an open picker's matches the rows above that.
    private static let rows = 20

    private static let listing = ProjectFiles(paths: (1 ... 12).map { "src/file\($0).swift" })

    private func rig(
        _ typed: String, files: Bool = false,
        options: ScreenOptions = ScreenOptions(prompt: "ask> ", tint: false, separator: false, padding: false),
        transcript: Int = 2,
        rows: Int = PickerClickTests.rows
    ) -> PointerRig {
        var rig = PointerRig(
            columns: 60, rows: rows, options: options, lines: (1 ... transcript).map { "line \($0)" })
        if files { rig.controller.handle(.files(Self.listing)) }
        type(typed, into: &rig)
        return rig
    }

    private func type(_ text: String, into rig: inout PointerRig, draw: Bool = true) {
        for scalar in text.unicodeScalars {
            _ = rig.controller.handle(.key(KeyEvent(keyCode: scalar.value)), pageRows: rig.buffer.rows - 3)
        }
        if draw { rig.draw() }
    }

    private func key(_ key: Key, in rig: inout PointerRig) {
        _ = rig.controller.handle(.key(KeyEvent(keyCode: key.rawValue)), pageRows: rig.buffer.rows - 3)
        rig.draw()
    }

    /// The row a label is drawn on, or nil.
    private func row(of label: String, in rig: PointerRig) -> Int? {
        (0 ..< Self.rows).first { rig.text(row: $0).hasPrefix(label) }
    }

    @Test func `a click on a command inserts it and sends nothing`() throws {
        var rig = rig("/")
        let target = try #require(row(of: "/jobs", in: rig))
        let effects = rig.click(row: target, col: 3)
        #expect(effects.isEmpty, "nothing is sent, run or copied")
        #expect(rig.controller.state.editor.text == "/jobs ")
        #expect(rig.controller.state.picker == nil)
        #expect(rig.text(row: Self.rows - 2) == "ask> /jobs")
    }

    @Test func `a click anywhere across the row counts, the last cell as much as the first`() throws {
        for column in [0, 10, 59] {
            var rig = rig("/")
            let target = try #require(row(of: "/quit", in: rig))
            rig.click(row: target, col: column)
            #expect(rig.controller.state.editor.text == "/quit ", "column \(column)")
        }
    }

    @Test func `a click on the title, the status line, the prompt or the transcript chooses nothing`() throws {
        var rig = rig("/")
        let first = try #require(row(of: "/help", in: rig))
        for target in [first - 1, first - 2, Self.rows - 1, 0, 5] {
            rig.click(row: target, col: 3)
            #expect(rig.controller.state.editor.text == "/", "row \(target)")
            #expect(rig.controller.state.picker != nil, "row \(target)")
        }
    }

    @Test func `a click in a long list chooses the row that was drawn there, after the window has scrolled`() throws {
        var rig = rig("@file", files: true)
        for _ in 0 ..< 9 { key(.down, in: &rig) }
        let target = try #require(row(of: "src/file10.swift", in: rig))
        #expect(rig.controller.state.picker?.firstVisible ?? 0 > 0, "the window scrolled")
        rig.click(row: target - 1, col: 4)
        #expect(rig.controller.state.editor.text == "@src/file9.swift ")
        #expect(rig.controller.state.picker == nil)
    }

    @Test func `a click on a file keeps a line range typed after it`() throws {
        var rig = rig("@file3:5-9", files: true)
        let target = try #require(row(of: "src/file3.swift", in: rig))
        rig.click(row: target, col: 2)
        #expect(rig.controller.state.editor.text == "@src/file3.swift:5-9 ")
    }

    @Test func `after a click the list is closed, so a second click lands on nothing it drew`() throws {
        var rig = rig("/")
        let target = try #require(row(of: "/jobs", in: rig))
        rig.click(row: target, col: 3)
        rig.click(row: target, col: 3, after: .milliseconds(50))
        #expect(rig.controller.state.editor.text == "/jobs ")
    }

    @Test func `a click on a frame the list has moved on from is ignored`() throws {
        var rig = rig("/")
        let target = try #require(row(of: "/jobs", in: rig))
        type("t", into: &rig, draw: false)  // the list narrowed, but the frame the mouse holds is still the old one
        rig.clock = rig.clock.advanced(by: .seconds(1))
        for kind in [MouseEventKind.press, .release] {
            let event = MouseEvent(button: .left, row: target + 1, col: 4, kind: kind)
            #expect(rig.controller.handle(.mouse(event), pageRows: 10, at: rig.clock).isEmpty)
        }
        #expect(rig.controller.state.editor.text == "/t", "the click meant a row that is no longer there")
        #expect(rig.controller.state.picker != nil)
    }

    @Test func `a click means the frame drawn when the button came up`() throws {
        var rig = rig("/")
        let target = try #require(row(of: "/jobs", in: rig))
        type("t", into: &rig)  // drawn: the list is shorter, and what the row says has changed
        let drawn = rig.text(row: target).split(separator: " ").first.map(String.init) ?? ""
        #expect(drawn.hasPrefix("/") && drawn != "/jobs", "the row now holds another match: \(drawn)")
        rig.click(row: target, col: 3)
        #expect(rig.controller.state.editor.text == drawn + " ")
    }

    @Test func `where the screen has room for fewer rows than the list holds, the row clicked is the match it shows`()
        throws
    {
        // Thirteen rows, a runners list plus separator and a two-line prompt: two matches fit below the title.
        // The third match must stay in view as the second of them.
        var rig = rig("/", rows: 13)
        rig.controller.handle(.runners((1 ... 7).map { RunnerInfo(name: "job-\($0)", detail: "sleep \($0)") }))
        rig.controller.state.runnersOpen = true
        _ = rig.controller.handle(.paste("\nsecond"), pageRows: 9)
        for _ in 0 ..< 7 { _ = rig.controller.handle(.key(KeyEvent(keyCode: Key.left.rawValue)), pageRows: 9) }
        key(.down, in: &rig)
        key(.down, in: &rig)
        let picker = try #require(rig.controller.state.picker)
        #expect(picker.selected == 3 && rig.controller.state.editor.text == "/\nsecond")
        let chosen = picker.matches[3].label
        let drawn = try #require((0 ..< 13).first { rig.text(row: $0).hasPrefix(chosen) }, "the choice is in view")
        #expect(rig.text(row: drawn - 2).hasPrefix("commands"), "the title, then two rows: \(drawn)")
        let above = try #require(rig.text(row: drawn - 1).split(separator: " ").first.map(String.init))
        #expect(above == picker.matches[2].label, "the row above the choice shows the second match")
        rig.click(row: drawn - 1, col: 3)
        #expect(rig.controller.state.editor.text == above + " \nsecond")
    }

    @Test func `with the mouse off nothing is clicked`() throws {
        var rig = rig(
            "/", options: ScreenOptions(mouse: false, prompt: "ask> ", tint: false, separator: false, padding: false))
        let target = try #require(row(of: "/jobs", in: rig))
        rig.click(row: target, col: 3)
        #expect(rig.controller.state.editor.text == "/")
    }

    @Test func `a question waiting for an answer hides the list, and a click there chooses nothing`() throws {
        var rig = rig("/")
        let target = try #require(row(of: "/jobs", in: rig))
        rig.controller.handle(.askApproval(id: 7, question: "bash wants network any. Allow it?"))
        rig.draw()
        #expect(
            rig.controller.frame.pickerWindow.isEmpty, "nothing of the list is drawn, so nothing of it is clickable")
        rig.click(row: target, col: 3)
        #expect(rig.controller.state.editor.text == "/")
    }

    @Test func `a question that arrives after the frame was drawn is not answered by a click on the old list`() throws {
        var rig = rig("/")
        let target = try #require(row(of: "/jobs", in: rig))
        rig.controller.handle(.askApproval(id: 7, question: "bash wants network any. Allow it?"))
        rig.clock = rig.clock.advanced(by: .seconds(1))
        for kind in [MouseEventKind.press, .release] {
            let event = MouseEvent(button: .left, row: target + 1, col: 4, kind: kind)
            _ = rig.controller.handle(.mouse(event), pageRows: 10, at: rig.clock)
        }
        #expect(rig.controller.state.editor.text == "/" && rig.controller.state.pendingApproval != nil)
    }

    @Test func `a drag that starts on a row selects nothing and inserts nothing`() throws {
        var rig = rig("/")
        let target = try #require(row(of: "/jobs", in: rig))
        rig.drag(from: (target, 2), to: (target, 8))
        #expect(rig.controller.state.editor.text == "/" && rig.controller.state.selection == nil)
    }

    @Test func `the wheel over the list still scrolls the transcript`() throws {
        var rig = rig("/", transcript: 40)
        let target = try #require(row(of: "/jobs", in: rig))
        rig.mouse(.scrollUp, .press, row: target, col: 3)
        #expect(rig.controller.state.scrollback > 0, "the transcript moved")
        #expect(rig.controller.state.editor.text == "/" && rig.controller.state.picker != nil)
    }
}
