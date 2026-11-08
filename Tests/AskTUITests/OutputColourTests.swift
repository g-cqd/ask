internal import TerminalKitCodecs
internal import TerminalKitInput
internal import TerminalKitStyle
internal import Testing

@testable import AskTUI

/// A command's own colours and links are drawn in its block (note n30): the block keeps the plain text, so nothing like `[1;31m` shows,
/// and the colour lands on the columns of the text it was asked for, over the output's dim.
@Suite("A tool block draws its output's own colours and links")
struct OutputColourTests {
    private static let esc = "\u{1B}"

    private func rows(_ output: String, columns: Int = 80, folded: Bool = false) -> [ScreenComposer.Line] {
        var transcript = Transcript()
        transcript.startTool(name: "shell", summary: "unused", id: "c", fullInput: "make", command: ToolCommand())
        transcript.finishTool(.succeeded, output: output, id: "c")
        transcript.setToolsFoldedByDefault(folded)
        return ScreenComposer.lines(in: transcript, at: 0, columns: columns)
    }

    private func row(_ rows: [ScreenComposer.Line], containing text: String) throws -> ScreenComposer.Line {
        try #require(rows.first { $0.text.contains(text) })
    }

    @Test func `the escapes are gone from the text, and the colour covers the word it was asked for`() throws {
        let shown = rows("build \(Self.esc)[1;31merror:\(Self.esc)[0m no such file")
        #expect(!shown.contains { $0.text.contains("[1;31m") || $0.text.contains("\u{1B}") })
        let line = try row(shown, containing: "build error: no such file")
        let start = try #require(line.text.firstRange(of: "error:")).lowerBound.utf16Offset(in: line.text)
        let accent = try #require(line.accents.first { $0.style.fg == .indexed(1) })
        #expect(accent.columns == start ..< start + 6)
        #expect(accent.style.bold && accent.style.dim, "bold, over the output's dim")
    }

    @Test func `a colour on a line after a tab lands on its text`() throws {
        let line = try row(rows("\tx \(Self.esc)[32mok\(Self.esc)[0m"), containing: "ok")
        let start = try #require(line.text.firstRange(of: "ok")).lowerBound.utf16Offset(in: line.text)
        #expect(line.accents.first { $0.style.fg == .indexed(2) }?.columns == start ..< start + 2)
    }

    @Test func `an OSC 8 link becomes the row's link over its text`() throws {
        let line = try row(
            rows("see \(Self.esc)]8;;https://example.com/doc\(Self.esc)\\the docs\(Self.esc)]8;;\(Self.esc)\\ now"),
            containing: "see the docs now"
        )
        let start = try #require(line.text.firstRange(of: "the docs")).lowerBound.utf16Offset(in: line.text)
        #expect(line.links.contains { $0.uri == "https://example.com/doc" && $0.columns == start ..< start + 8 })
    }

    @Test func `a long output's tail keeps its own colours when the middle is folded away`() throws {
        let lines = (1 ... 300).map { $0 == 300 ? "\(Self.esc)[33mlast line\(Self.esc)[0m" : "line \($0)" }
        let shown = rows(lines.joined(separator: "\n"))
        #expect(!shown.contains { $0.text.hasSuffix("line 150") }, "the middle is folded away")
        let line = try row(shown, containing: "last line")
        let start = try #require(line.text.firstRange(of: "last line")).lowerBound.utf16Offset(in: line.text)
        #expect(line.accents.first { $0.style.fg == .indexed(3) }?.columns == start ..< start + 9)
    }

    @Test func `a job's lane shows its output without escapes`() {
        var rig = PointerRig(columns: 60, rows: 16, lines: ["first"])
        rig.controller.handle(.runners([RunnerInfo(name: "job-1", detail: "npm run dev")]))
        rig.controller.state.runnersOpen = true
        for code in [Key.down.rawValue, Key.enter.rawValue] {
            _ = rig.controller.handle(.key(KeyEvent(keyCode: code)), pageRows: 12)
        }
        rig.controller.handle(
            .runnerOutput(id: "job-1", text: "\(Self.esc)[1;31merror:\(Self.esc)[0m port\(Self.esc)]0;t\u{07} taken")
        )
        rig.draw()
        let screen = (0 ..< 16).map { rig.text(row: $0) }.joined(separator: "\n")
        #expect(screen.contains("error: port taken") && !screen.contains("[1;31m"))
    }

    @Test func `an underline's kind and a strikethrough are drawn`() throws {
        let line = try row(
            rows("\(Self.esc)[4:3mwavy\(Self.esc)[24;9m struck\(Self.esc)[0m"),
            containing: "wavy struck"
        )
        #expect(line.accents.contains { $0.style.underline == .curly && !$0.style.strikethrough })
        #expect(line.accents.contains { $0.style.strikethrough && $0.style.underline == .none })
    }

    @Test func `a link alone adds no accent: its row's link is how it shows`() throws {
        let line = try row(
            rows("\(Self.esc)]8;;https://example.com\(Self.esc)\\site\(Self.esc)]8;;\(Self.esc)\\"),
            containing: "site"
        )
        #expect(line.links.contains { $0.uri == "https://example.com" })
        #expect(line.accents.isEmpty)
    }

    @Test func `a file tool's output keeps its own colours, and a write keeps its input's language`() throws {
        var read = Transcript()
        read.startTool(name: "read", summary: "notes.txt", id: "r", path: "notes.txt")
        read.finishTool(.succeeded, output: "\(Self.esc)[31mred\(Self.esc)[0m", id: "r")
        #expect(try #require(read.fileCode(at: 0)).spans != nil)
        var write = Transcript()
        write.setHighlight(true)
        write.startTool(name: "write", summary: "a.swift", id: "w", fullInput: "let a = 1", path: "a.swift")
        write.finishTool(.succeeded, output: "\(Self.esc)[32mwritten\(Self.esc)[0m", id: "w")
        let code = try #require(write.fileCode(at: 0))
        #expect(code.part == .input && code.spans == nil)
    }

    @Test func `output with no escape draws as before`() {
        #expect(rows("plain output").allSatisfy { $0.accents.allSatisfy { $0.style.fg != .indexed(1) } })
    }
}
