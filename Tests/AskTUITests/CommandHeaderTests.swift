internal import Foundation
internal import TerminalKitStyle
internal import TerminalKitText
internal import Testing

@testable import AskTUI

/// A command heads its tool block after its limits, fills the row up to the status, and opens in place (roadmap 0080).
@Suite("A command heads its block and opens in place")
struct CommandHeaderTests {
    private func transcript(
        _ command: String, output: String = "RESULT", limits: ToolCommand = ToolCommand(), localized: Bool = true,
        folded: Bool = true
    ) -> Transcript {
        var result = Transcript()
        result.localizedDurations = localized
        result.startTool(name: "shell", summary: "unused", id: "c", fullInput: command, command: limits)
        result.finishTool(.succeeded, output: output, id: "c")
        result.setToolsFoldedByDefault(folded)
        return result
    }

    private func rows(_ transcript: Transcript, columns: Int) -> [ScreenComposer.Line] {
        ScreenComposer.lines(in: transcript, at: 0, columns: columns)
    }

    @Test func `the limits come before the command, and without limits there is only the tool`() throws {
        let limited = transcript("ls -la", limits: ToolCommand(timeout: .seconds(120)), localized: false)
        #expect(try #require(rows(limited, columns: 80).first).text.hasPrefix("shell · timeout 2:00 · ls -la  "))
        let both = transcript("ls", limits: ToolCommand(timeout: .seconds(90), yield: .seconds(5)), localized: false)
        #expect(try #require(rows(both, columns: 80).first).text.hasPrefix("shell · timeout 1:30 · yield 0:05 · ls  "))
        #expect(try #require(rows(transcript("ls -la"), columns: 80).first).text.hasPrefix("shell · ls -la  "))
    }

    @Test func `the limits are written in the locale's units by default`() {
        let english = ToolCommand(timeout: .seconds(120), yield: .seconds(5))
            .parameters(localized: true, locale: Locale(identifier: "en_US"))
        #expect(english == "timeout 2 min · yield 5 sec")
        #expect(ToolCommand().parameters(localized: true).isEmpty)
    }

    @Test func `folded, a long command fills the row up to the status at every width, and never wraps`() throws {
        let command = "swift test --filter " + String(repeating: "Suite", count: 60)
        for columns in [20, 33, 50, 80, 132, 300] {
            let shown = rows(transcript(command), columns: columns)
            #expect(shown.count == 1, "\(columns) columns")
            let row = try #require(shown.first)
            #expect(UnicodeWidth.displayWidth(of: row.text) == columns, "\(columns) columns")
            #expect(row.text.hasSuffix("…  1 line · ✓"), "\(columns) columns: \(row.text)")
        }
    }

    @Test func `wide characters are cut by display cells`() throws {
        let command = "echo " + String(repeating: "界", count: 60)
        for columns in [30, 31, 47] {
            let row = try #require(rows(transcript(command), columns: columns).first)
            #expect(UnicodeWidth.displayWidth(of: row.text) == columns, "\(columns) columns: \(row.text)")
            // A two-cell character that does not fit leaves one cell, which widens the gap rather than splitting the character.
            #expect(row.text.contains("…  1 line · ✓") || row.text.contains("…   1 line · ✓"), "\(row.text)")
        }
    }

    @Test func `a command that fits is not cut, and a multi-line one says there is more`() throws {
        let short = try #require(rows(transcript("ls"), columns: 40).first).text
        #expect(short == "shell · ls" + String(repeating: " ", count: 20) + "1 line · ✓")
        let multi = try #require(rows(transcript("cd /tmp\nls"), columns: 40).first)
        #expect(multi.text.hasPrefix("shell · cd /tmp …  "))
    }

    @Test func `open, the command is shown once: its first line heads the block and the rest follows`() throws {
        let command = "cd /tmp\nls -la\necho done"
        let open = rows(transcript(command, output: "a\nb", folded: false), columns: 60).map(\.text)
        #expect(open.first?.hasPrefix("shell · cd /tmp  ") == true)
        #expect(open.filter { $0.contains("cd /tmp") }.count == 1)
        #expect(Array(open.dropFirst().prefix(2)) == ["ls -la", "echo done"])
        #expect(open.suffix(2) == ["a", "b"])
    }

    @Test func `open, a long single line continues below the header at full width`() {
        let command = String(repeating: "abcdefghij", count: 12)
        let open = rows(transcript(command, folded: false), columns: 40)
        #expect(open.allSatisfy { UnicodeWidth.displayWidth(of: $0.text) <= 40 })
        let shown = open.compactMap { $0.source?.line == 0 ? $0.source?.text : nil }.joined()
        #expect(shown == "shell · " + command, "the command is complete, once, across the rows")
    }

    @Test func `a selection copies what is shown, folded or open`() {
        let command = "cd /tmp\nls"
        #expect(transcript(command).contentText(at: 0) == "shell · cd /tmp …")
        #expect(transcript(command, folded: false).contentText(at: 0) == "shell · cd /tmp\nls\nRESULT")
    }

    @Test func `a heredoc in the command still folds from its own lines`() throws {
        let body = (0 ..< 50).map { "line \($0)" }
        let command = (["cat << 'EOF' > a.txt"] + body + ["EOF", "echo after"]).joined(separator: "\n")
        var open = transcript(command, folded: false)
        // Folded by default: the opener heads the block, twenty lines follow, then the placeholder that opens it.
        #expect(open.codeFence(toggledByLine: 0, at: 0) == nil)
        let placeholder = try #require(open.codeFence(toggledByLine: 21, at: 0))
        let before = rows(open, columns: 80).map(\.text)
        #expect(before.contains("[… 30 lines embedded heredoc …]"))
        open.toggleCodeFold(placeholder, at: 0)
        #expect(rows(open, columns: 80).count == before.count + 30 - 1)
        // Open, the opener, which is the header's own row, folds it again.
        #expect(open.codeFence(toggledByLine: 0, at: 0) == placeholder)
    }

    @Test func `open, the command is drawn bright while its lead, status and output stay dim`() throws {
        let open = rows(
            transcript("cd /tmp\nls -la", output: "a", limits: ToolCommand(timeout: .seconds(5)), folded: false),
            columns: 60)
        let header = try #require(open.first)
        #expect(header.style.dim, "the lead and the status keep the status colour")
        let lead = "shell · timeout 5 sec · "
        let accent = try #require(header.accents.first)
        #expect(accent.style == ScreenComposer.commandStyle && !accent.style.dim)
        #expect(accent.columns == lead.count ..< lead.count + "cd /tmp".count)
        let next = try #require(open.first { $0.text == "ls -la" })
        #expect(next.style == ScreenComposer.commandStyle)
        #expect(try #require(open.last { $0.text == "a" }).style.dim, "the output stays dim")
        let folded = try #require(
            rows(transcript("cd /tmp", limits: ToolCommand(timeout: .seconds(5))), columns: 60).first)
        #expect(folded.style.dim && folded.accents.isEmpty, "a folded block is unchanged")
    }
}
