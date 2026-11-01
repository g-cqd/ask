import Foundation
import TerminalKitStyle
internal import Testing

@testable import AskTUI

/// `read` output and `write` content coloured by the language of the path they name (roadmap 0152, phase 3).
@Suite("File tool blocks are coloured by their path's language")
struct FileHighlightTests {
    private static func transcript(
        _ name: String,
        path: String?,
        input: String,
        output: String,
        failed: Bool = false,
        highlight: Bool = true,
        summary: String? = nil
    ) -> Transcript {
        var transcript = Transcript()
        transcript.setHighlight(highlight)
        transcript.setOutputFoldLimits(lines: 10, bytes: 1 << 20)
        transcript.startTool(name: name, summary: summary ?? path ?? "", id: "call", fullInput: input, path: path)
        transcript.finishTool(failed ? .failed(output) : .succeeded, output: output, id: "call")
        transcript.setToolsFoldedByDefault(false)
        return transcript
    }

    /// Every drawn run of the block, as text and style, row by row.
    private static func runs(_ transcript: Transcript, columns: Int = 80) -> [[(String, Style)]] {
        ScreenComposer.lines(in: transcript, at: 0, columns: columns)
            .map { ScreenComposer.spans(of: $0, highlight: nil) }
    }

    /// The style of the first run whose text, without surrounding spaces, is `text`.
    private static func style(of text: String, in transcript: Transcript, columns: Int = 80) -> Style? {
        runs(transcript, columns: columns).joined().first { $0.0.trimmingCharacters(in: .whitespaces) == text }?.1
    }

    private static let read = "{\n  \"path\": \"a.swift\"\n}"

    @Test func `a read swift file has its keywords and comments coloured, and stays dim as output`() throws {
        let transcript = Self.transcript(
            "read",
            path: "Sources/a.swift",
            input: Self.read,
            output: "func f() -> Int {\n\treturn 1 // done\n}"
        )
        let keyword = try #require(Self.style(of: "func", in: transcript))
        #expect(keyword.fg == .indexed(5))
        #expect(keyword.dim, "output is dim, and its colours keep that")
        let comment = try #require(Self.style(of: "// done", in: transcript))
        #expect(comment.italic && comment.dim)
        #expect(Self.style(of: "1", in: transcript)?.fg == .indexed(3))
    }

    @Test func `what a write puts in a file is coloured in the default brightness`() throws {
        let transcript = Self.transcript(
            "write",
            path: "b.json",
            input: "{\"key\": [\"s\", true]}",
            output: "Wrote 20 bytes to b.json."
        )
        let string = try #require(Self.style(of: "\"s\"", in: transcript))
        #expect(string.fg == .indexed(2))
        #expect(!string.dim)
        let acknowledgement = Self.runs(transcript).joined().filter { $0.0.contains("Wrote") }
        #expect(acknowledgement.allSatisfy { $0.1.fg == .default }, "the tool's own sentence is not code")
    }

    @Test func `the read's own line saying which lines it shows is not coloured`() {
        let transcript = Self.transcript(
            "read",
            path: "tool.py",
            input: Self.read,
            output: "x = 1\ny = 2\n[lines 2–3 of 3]"
        )
        let trailer = Self.runs(transcript).first { $0.map(\.0).joined().contains("[lines") }
        #expect(trailer?.count == 1, "one run: the row as it is")
    }

    @Test func `a file with no extension takes its language from a #! line`() {
        let transcript = Self.transcript("read", path: "run", input: Self.read, output: "#!/bin/sh\necho \"$HOME\"")
        #expect(Self.style(of: "\"$HOME\"", in: transcript)?.fg == .indexed(2))
    }

    @Test func `an unknown language, a failed read, highlighting off and other tools draw as before`() {
        let cases = [
            ("read", "notes.txt", "func f() {}", false, true), ("read", "a.swift", "func f() {}", true, true),
            ("read", "a.swift", "func f() {}", false, false), ("shell", "a.swift", "func f() {}", false, true)
        ]
        for (name, path, output, failed, highlight) in cases {
            let shown = Self.transcript(
                name,
                path: path,
                input: Self.read,
                output: output,
                failed: failed,
                highlight: highlight
            )
            let plain = Self.transcript(
                name,
                path: nil,
                input: Self.read,
                output: output,
                failed: failed,
                highlight: false,
                summary: path
            )
            #expect(
                ScreenComposer.lines(in: shown, at: 0, columns: 80)
                    == ScreenComposer.lines(in: plain, at: 0, columns: 80),
                "\(name) \(path) failed \(failed) highlight \(highlight)"
            )
        }
    }

    @Test func `colours land on the right columns past tabs and wide characters, and follow a token onto the next row`()
        throws
    {
        let output = "\tlet 漢字 = \"é and a string long enough to wrap\" // end"
        let transcript = Self.transcript("read", path: "a.swift", input: Self.read, output: output)
        #expect(Self.style(of: "let", in: transcript)?.fg == .indexed(5))
        #expect(Self.style(of: "// end", in: transcript, columns: 200)?.italic == true)
        // At 24 columns the string spans several rows; every piece of it is a string's colour.
        let rows = Self.runs(transcript, columns: 24)
        let pieces = rows.joined().filter { $0.0.contains("string") || $0.0.contains("wrap") || $0.0.contains("é") }
        #expect(!pieces.isEmpty)
        #expect(pieces.allSatisfy { $0.1.fg == .indexed(2) })
    }

    @Test
    func `the path a tool update names reaches the block, and turning highlighting on lays file blocks out again`() {
        var controller = ScreenController(label: "test")
        _ = controller.handle(.toolStarted(name: "read", summary: "a.swift", id: "r", fullInput: "{}", path: "a.swift"))
        _ = controller.handle(.toolStarted(name: "shell", summary: "ls", id: "s", fullInput: "ls"))
        #expect(controller.state.transcript.toolPaths == [0: "a.swift"])
        var transcript = controller.state.transcript
        let before = transcript.revisions
        transcript.setHighlight(!transcript.highlight)
        #expect(transcript.revisions[0] != before[0], "the read is drawn again")
        #expect(transcript.revisions[1] == before[1], "the shell block is not")
    }

    @Test func `wrapping a line never changes the colour of any of its characters`() {
        let output = "\tlet 漢字 = \"é, 🇫🇷 and text\" + f(0x1F) // 終わり end\nlet ascii = \"plain\" // c"
        let transcript = Self.transcript("read", path: "a.swift", input: Self.read, output: output)
        let reference = Self.characterStyles(transcript, columns: 400)
        #expect(reference.values.contains { $0.fg == .indexed(2) } && reference.values.contains { $0.italic })
        for columns in 3 ... 60 {
            let wrapped = Self.characterStyles(transcript, columns: columns)
            for (place, style) in wrapped {
                #expect(reference[place] == style, "\(columns) columns, line \(place.line), grapheme \(place.offset)")
            }
        }
    }

    /// The style each grapheme of the output is drawn in, by its hard line and grapheme offset in that line.
    private static func characterStyles(_ transcript: Transcript, columns: Int) -> [Place: Style] {
        var result: [Place: Style] = [:]
        for line in ScreenComposer.lines(in: transcript, at: 0, columns: columns) {
            guard let source = line.source, source.line >= 4 else { continue }
            var offset = source.offset
            for (text, style) in ScreenComposer.spans(of: line, highlight: nil) {
                for _ in text {
                    result[Place(line: source.line, offset: offset)] = style
                    offset += 1
                }
            }
        }
        return result
    }

    struct Place: Hashable {
        var line: Int
        var offset: Int
    }

    @Test func `the tail of a folded output is lexed afresh, not as the rest of the head`() throws {
        let output = (["/* opened in the head"] + (2 ... 30).map { "let v\($0) = \($0)" }).joined(separator: "\n")
        let transcript = Self.transcript("read", path: "a.swift", input: Self.read, output: output)
        // The head's lines are all inside the comment, so a `let` run of its own can only be the tail's.
        #expect(Self.style(of: "let", in: transcript)?.fg == .indexed(5), "the tail's keywords are keywords")
    }
}
