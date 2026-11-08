import AemiLexers
import Foundation
import TerminalKitStyle
import TerminalKitText
internal import Testing

@testable import AskTUI

/// Tool output recognised by its content (roadmap 0152, phase 5): JSON is coloured as JSON, and a unified diff takes an edit's row tints,
/// with its headers set apart and, when its files share one language, its code coloured. Nothing else is guessed at.
@Suite("Tool output that is JSON or a unified diff is coloured as such")
struct RecognisedOutputTests {
    private static let diff = """
        diff --git a/Sources/a.swift b/Sources/a.swift
        index 1111111..2222222 100644
        --- a/Sources/a.swift
        +++ b/Sources/a.swift
        @@ -1,3 +1,3 @@
         let a = 1
        -let b = "old"
        +let b = "new"
        --- old comment line
        """

    private static func transcript(
        _ output: String,
        name: String = "shell",
        highlight: Bool = true,
        running: Bool = false
    ) -> Transcript {
        var transcript = Transcript()
        transcript.setHighlight(highlight)
        transcript.setOutputFoldLimits(lines: 100, bytes: 1 << 20)
        transcript.startTool(name: name, summary: "git diff", id: "c", fullInput: "git diff")
        if !running { transcript.finishTool(.succeeded, output: output, id: "c") }
        transcript.setToolsFoldedByDefault(false)
        return transcript
    }

    private static func row(_ text: String, in transcript: Transcript) -> ScreenComposer.Line? {
        ScreenComposer.lines(in: transcript, at: 0, columns: 80, style: BlockStyle()).first { $0.text.contains(text) }
    }

    private static func runs(_ line: ScreenComposer.Line?) -> [(String, Style)] {
        line.map { ScreenComposer.spans(of: $0, highlight: nil) } ?? []
    }

    @Test func `a long diff's tail is lexed afresh only while its middle is folded away`() throws {
        let long = """
            diff --git a/Sources/a.swift b/Sources/a.swift
            --- a/Sources/a.swift
            +++ b/Sources/a.swift
            @@ -1,1 +1,41 @@
             let a = 1
            """ + String(repeating: "\n+let c = 3", count: 40)
        var transcript = Self.transcript(long)
        transcript.setOutputFoldLimits(lines: 10, bytes: 1 << 20)
        transcript.setCodeFoldedByDefault(true)
        let folded = try #require(transcript.fileCode(at: 0))
        #expect(folded.restart != nil && folded.restart == transcript.shownToolOutput(at: 0)?.markerLine)
        transcript.setCodeFoldedByDefault(false)
        #expect(try #require(transcript.fileCode(at: 0)).restart == nil, "open, the text is whole and lexed as one")
    }

    @Test func `JSON output is coloured as JSON, and stays dim as output`() throws {
        for name in ["shell", "mcp_call"] {
            let transcript = Self.transcript(#"{"name": "ask", "count": 3}"#, name: name)
            let value = try #require(Self.runs(Self.row("ask", in: transcript)).first { $0.0.contains(#""ask""#) })
            #expect(value.1.fg == .indexed(2) && value.1.dim, "\(name)")
        }
    }

    @Test func `output that only looks like JSON stays plain`() {
        for text in ["{ not json", "[1, 2", "status: {ok}"] {
            let transcript = Self.transcript(text)
            #expect(
                Self.runs(Self.row(String(text.prefix(4)), in: transcript)).allSatisfy { $0.1.fg == .default },
                "\(text)"
            )
        }
    }

    @Test func `a unified diff takes the edit's tints, its headers set apart and its code coloured`() throws {
        let theme = BlockStyle().theme
        let transcript = Self.transcript(Self.diff)
        #expect(try #require(Self.row(#"+let b = "new""#, in: transcript)).style.bg == theme.diffAdded)
        #expect(try #require(Self.row(#"-let b = "old""#, in: transcript)).style.bg == theme.diffRemoved)
        #expect(
            try #require(Self.row("--- old comment line", in: transcript)).style.bg == theme.diffRemoved,
            "in a hunk, a line starting --- is a removed line"
        )
        #expect(try #require(Self.row("diff --git", in: transcript)).style.bold)
        #expect(try #require(Self.row("+++ b/Sources", in: transcript)).style.bold, "before the hunk, +++ is a header")
        #expect(try #require(Self.row("@@ -1,3", in: transcript)).style.fg == .indexed(6))
        let added = Self.runs(Self.row(#"+let b = "new""#, in: transcript))
        #expect(added.first { $0.0.hasPrefix("+") }?.1.fg == .indexed(2))
        #expect(added.contains { $0.0.trimmingCharacters(in: .whitespaces) == "let" && $0.1.fg == .indexed(5) })
    }

    @Test func `a diff of files in several languages keeps its tints but colours no code`() throws {
        let text = Self.diff + "\n--- a/b.py\n+++ b/b.py\n@@ -1 +1 @@\n-x = 1\n+x = 2"
        let added = Self.runs(Self.row(#"+let b = "new""#, in: Self.transcript(text)))
        #expect(!added.contains { $0.1.fg == .indexed(5) })
        #expect(
            try #require(Self.row(#"+let b = "new""#, in: Self.transcript(text))).style.bg
                == BlockStyle().theme.diffAdded
        )
    }

    @Test func `with highlighting off, or while the command runs, the output is drawn as before`() throws {
        let theme = BlockStyle().theme
        for transcript in [
            Self.transcript(Self.diff, highlight: false), Self.transcript(#"{"a": 1}"#, highlight: false)
        ] {
            for row in ScreenComposer.lines(in: transcript, at: 0, columns: 80, style: BlockStyle()) {
                #expect(row.accents.isEmpty && (row.style.bg == theme.success || row.style.bg == .default))
            }
        }
        var running = Self.transcript("", running: true)
        running.items[0] = .tool(
            name: "shell",
            summary: "git diff",
            status: .running,
            output: Self.diff,
            fullInput: "git diff"
        )
        for row in ScreenComposer.lines(in: running, at: 0, columns: 80, style: BlockStyle()) {
            #expect(row.style.bg != theme.diffAdded)
        }
    }

    @Test func `recognition reads the content alone`() {
        #expect(RecognisedOutput.recognise(Self.diff) == .diff(.swift))
        #expect(RecognisedOutput.recognise(Self.diff + "\n--- a/b.py\n+++ b/b.py\n@@ -1 +1 @@\n-x = 1") == .diff(nil))
        #expect(RecognisedOutput.recognise("--- a/notes.txt\n+++ b/notes.txt\n@@ -1 +1 @@\n-a\n+b") == .diff(nil))
        #expect(RecognisedOutput.recognise("--- a/x.swift\n+++ b/x.swift\nno hunk") == nil)
        #expect(RecognisedOutput.recognise("@@ -1 +1 @@\n-a\n+b") == nil, "a hunk with no file header is not a diff")
        #expect(RecognisedOutput.recognise("  [1, {\"a\": null}]\n") == .json)
        #expect(RecognisedOutput.recognise("plain words") == nil)
    }

    @Test func `each file of a diff is lexed afresh after its header`() throws {
        let text = """
            diff --git a/a.swift b/a.swift
            --- a/a.swift
            +++ b/a.swift
            @@ -1 +1 @@
            +let a = 1 /* never closed
            diff --git a/b.swift b/b.swift
            --- a/b.swift
            +++ b/b.swift
            @@ -1 +1 @@
            +let b = 2
            """
        let added = Self.runs(Self.row("+let b = 2", in: Self.transcript(text)))
        #expect(
            added.contains {
                $0.0.trimmingCharacters(in: .whitespaces) == "let" && $0.1.fg == .indexed(5) && !$0.1.italic
            }
        )
    }
}
