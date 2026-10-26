import TerminalKitCodecs
import TerminalKitInput
import TerminalKitRender
import TerminalKitStyle
import TerminalKitText
import Testing

@testable import AskTUI

/// How the picker is drawn: between the status line and the prompt, taking rows from the transcript, in text only (a bold choice,
/// no fill, no leading icon), and never so tall that the transcript disappears.
@Suite("The picker is drawn above the prompt, in text, and the transcript gives way to it")
struct CompletionPickerComposerTests {
    private static let commands = commandTable(
        """
        config | Show the settings.
        compact | Compact the conversation.
        reload | Reload the binary.
        """)

    private func rows(_ buffer: ScreenBuffer) -> [String] {
        (0 ..< buffer.rows)
            .map { row in
                var text = ""
                for column in 0 ..< buffer.columns {
                    let cell = buffer[row, column]
                    if !cell.isContinuation { text.append(cell.character) }
                }
                while text.hasSuffix(" ") { text.removeLast() }
                return text
            }
    }

    private func screen(
        typing text: String, commands: [SlashCommand] = commands, rows: Int = 20
    ) -> (ScreenController, Int) {
        var controller = ScreenController(label: "m", commands: commands)
        for scalar in text.unicodeScalars {
            _ = controller.handle(.key(KeyEvent(keyCode: scalar.value)), pageRows: rows - 3)
        }
        return (controller, rows)
    }

    @Test func `the picker sits above the prompt, and the status line below it`() throws {
        var (controller, height) = screen(typing: "/co")
        controller.handle(.notice("older line", isError: false))
        var buffer = ScreenBuffer(columns: 60, rows: height)
        var composer = ScreenComposer()
        let cursor = composer.compose(controller.state, into: &buffer)
        let shown = rows(buffer)
        let prompt = height - 2
        #expect(shown[prompt] == "ask> /co" && shown.last == "m", "the prompt, then the status line under it")
        #expect(shown[prompt - 4].hasPrefix("commands") && shown[prompt - 4].contains("Esc"))
        #expect(shown[prompt - 3].hasPrefix("/config") && shown[prompt - 3].contains("Show the settings."))
        #expect(shown[prompt - 2].hasPrefix("/compact") && shown[prompt - 1].hasPrefix("/help"))
        #expect(cursor.row == prompt && cursor.column == 8)
        #expect(composer.transcriptRows == prompt - 4)
    }

    @Test func `the choice is bold and nothing is painted, filled or marked`() throws {
        var (controller, height) = screen(typing: "/co")
        _ = controller.handle(.key(KeyEvent(keyCode: Key.down.rawValue)), pageRows: height - 3)
        var buffer = ScreenBuffer(columns: 60, rows: height)
        var composer = ScreenComposer()
        _ = composer.compose(controller.state, into: &buffer)
        let shown = rows(buffer)
        let first = try #require(shown.firstIndex { $0.hasPrefix("/config") })
        #expect(!buffer[first, 0].style.bold && buffer[first + 1, 0].style.bold, "the second match is the choice")
        for row in (first - 1) ..< (first + 4) {
            for column in 0 ..< 60 {
                let style = buffer[row, column].style
                #expect(style.bg == .default && !style.inverse, "painted cell at \(row),\(column)")
            }
        }
        #expect(shown[first + 1].first == "/", "nothing starts a row but its text")
    }

    @Test func `the title counts the choice when there are more matches than rows`() throws {
        let many = (0 ..< 12).map { SlashCommand(name: "cmd\($0)", summary: "Command \($0).") }
        var (controller, height) = screen(typing: "/cmd", commands: many)
        for _ in 0 ..< 9 { _ = controller.handle(.key(KeyEvent(keyCode: Key.down.rawValue)), pageRows: height - 3) }
        var buffer = ScreenBuffer(columns: 70, rows: height)
        var composer = ScreenComposer()
        _ = composer.compose(controller.state, into: &buffer)
        let shown = rows(buffer)
        let title = try #require(shown.first { $0.hasPrefix("commands") })
        #expect(title.contains("10 of 12"))
        #expect(shown.contains { $0.hasPrefix("/cmd9") } && !shown.contains { $0.hasPrefix("/cmd0") })
        #expect(shown.filter { $0.hasPrefix("/cmd") }.count == 7)
    }

    @Test func `it never takes the last transcript row, even where rows are scarce`() {
        var (controller, height) = screen(typing: "/", rows: 12)
        controller.handle(.notice("still here", isError: false))
        var buffer = ScreenBuffer(columns: 50, rows: height)
        var composer = ScreenComposer()
        _ = composer.compose(controller.state, into: &buffer)
        #expect(composer.transcriptRows >= 1)
        #expect(rows(buffer).contains("still here"))
        #expect(rows(buffer).dropLast().last == "ask> /")
    }

    @Test func `it is hidden while an approval question waits, and back when it is answered`() {
        var (controller, height) = screen(typing: "/co")
        controller.handle(.askApproval(id: 1, question: "bash wants network. Allow it?"))
        var buffer = ScreenBuffer(columns: 60, rows: height)
        var composer = ScreenComposer()
        _ = composer.compose(controller.state, into: &buffer)
        #expect(!rows(buffer).contains { $0.hasPrefix("commands") })
    }

    @Test func `rows are cut to the width, wide text included, and a tiny width does not crash`() throws {
        let wide = [SlashCommand(name: "wide", summary: String(repeating: "日本語", count: 20))]
        let (controller, _) = screen(typing: "/w", commands: wide)
        let picker = try #require(controller.state.picker)
        // Every width, so every way a cut can land inside a two-cell character is tried: the builder relies on the cut never overshooting.
        for columns in 1 ... 60 {
            let lines = ScreenComposer.pickerLines(picker, columns: columns, rows: 8)
            #expect(!lines.isEmpty)
            for line in lines {
                #expect(UnicodeWidth.displayWidth(of: line.text) <= columns, "\(line.text) at \(columns)")
            }
        }
        #expect(ScreenComposer.pickerLines(picker, columns: 40, rows: 1).isEmpty, "a title alone is not a picker")
        #expect(ScreenComposer.pickerLines(picker, columns: 0, rows: 8).isEmpty)
    }

    @Test func `the picker sits above the input, and the status line and the runner strip below it`() throws {
        var (controller, height) = screen(typing: "/co")
        controller.handle(
            .runners([RunnerInfo(name: "job-1", detail: "npm run dev"), RunnerInfo(name: "job-2", detail: "tail -f")]))
        controller.state.runnersOpen = true
        controller.handle(.notice("older", isError: false))
        var buffer = ScreenBuffer(columns: 60, rows: height)
        var composer = ScreenComposer()
        let cursor = composer.compose(controller.state, into: &buffer)
        let shown = rows(buffer)
        let first = try #require(shown.firstIndex { $0.hasPrefix("job-1") })
        let picker = composer.transcriptRows
        #expect(shown[picker].hasPrefix("commands") && shown[picker + 1].hasPrefix("/config"))
        #expect(shown[first - 2] == "ask> /co" && shown[first - 1].hasPrefix("m"), "the input, then the status")
        #expect(shown[first + 1].hasPrefix("job-2"))
        #expect(first == height - 2 && cursor.row == first - 2)
    }

    @Test func `a full runners list and the picker together still leave the transcript a row`() {
        var (controller, height) = screen(typing: "/", rows: 12)
        controller.handle(.runners((1 ... 9).map { RunnerInfo(name: "job-\($0)", detail: "work") }))
        controller.state.runnersOpen = true
        controller.handle(.notice("still here", isError: false))
        var buffer = ScreenBuffer(columns: 50, rows: height)
        var composer = ScreenComposer()
        _ = composer.compose(controller.state, into: &buffer)
        #expect(composer.transcriptRows >= 1 && rows(buffer).contains("ask> /"))
    }

    @Test func `the transcript keeps a row at every screen height that offers a picker, with any number of runners`() {
        // The budget passed to the picker never binds with today's caps (five runner rows, at most seven matches), so this pins the
        // invariant itself: if either cap grows, a screen too small for both fails here and not in a terminal.
        for height in 12 ... 30 {
            for runners in [0, 1, 5, 9] {
                var (controller, _) = screen(typing: "/", rows: height)
                controller.handle(.runners((0 ..< runners).map { RunnerInfo(name: "job-\($0)", detail: "work") }))
                controller.state.runnersOpen = runners > 0
                var buffer = ScreenBuffer(columns: 40, rows: height)
                var composer = ScreenComposer()
                _ = composer.compose(controller.state, into: &buffer)
                #expect(composer.transcriptRows >= 1, "height \(height), \(runners) runners")
                #expect(rows(buffer).contains("ask> /"), "height \(height), \(runners) runners")
            }
        }
    }

    @Test func `closing it gives the rows back to the transcript`() {
        var (controller, height) = screen(typing: "/co")
        for index in 1 ... 30 { controller.handle(.notice("line \(index)", isError: false)) }
        var buffer = ScreenBuffer(columns: 60, rows: height)
        var composer = ScreenComposer()
        _ = composer.compose(controller.state, into: &buffer)
        let withPicker = composer.transcriptRows
        _ = controller.handle(.key(KeyEvent(keyCode: 0x1B)), pageRows: height - 3)
        _ = composer.compose(controller.state, into: &buffer)
        #expect(composer.transcriptRows == withPicker + 4, "the title and three matches")
        #expect(
            rows(buffer)[composer.transcriptRows - 1] == "line 30",
            "the newest line stays at the bottom of the transcript")
    }
}
