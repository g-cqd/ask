import AemiJSON
import AskAI
import Foundation
import Testing

@testable import AskAgentCore

@Suite("Tool presentation preserves full input and separates target from parameters")
struct ToolPresentationTests {
    static let english = Locale(identifier: "en_US")
    static let german = Locale(identifier: "de_DE")

    private func input(_ json: String) throws -> JSONObject { try JSONObject(validating: Array(json.utf8)) }

    @Test func `complete multiline shell commands are not reduced to the header`() throws {
        let command = String(repeating: "x", count: 200) + "\nsecond line"
        let json = try input(
            #"{"command":"\#(String(repeating: "x", count: 200))\nsecond line","timeout_seconds":60,"yield_seconds":5}"#
        )
        #expect(ToolSummary.fullInput(for: json) == command)
        #expect(
            ToolSummary.header(for: json).hasPrefix("timeout 60s · yield 5s · "),
            "the limits before the command (roadmap 0080)"
        )
        #expect(!ToolSummary.header(for: json).contains("second line"))
    }

    @Test func `the path a file call names is given as written, and nil for a call without one`() throws {
        #expect(ToolSummary.path(for: try input(#"{"path":"~/src/a.swift","offset":10}"#)) == "~/src/a.swift")
        #expect(ToolSummary.path(for: try input(#"{"command":"ls"}"#)) == nil)
    }

    /// Modifiers before the subject, as the shell's limits are (the owner's choice, 2026-11-02, roadmap 0080): a long path cut at the
    /// edge never hides them.
    @Test func `read and write headers show their lines and size before the path`() throws {
        #expect(
            ToolSummary.header(for: try input(#"{"path":"src/a.swift","offset":10,"limit":36}"#))
                == "lines 10–45 · src/a.swift"
        )
        #expect(
            ToolSummary.header(for: try input(#"{"path":"src/b.swift","offset":15}"#))
                == "from line 15 · src/b.swift"
        )
        #expect(ToolSummary.header(for: try input(#"{"path":"a.txt","content":"é"}"#)) == "2 B · a.txt")
        let kb = String(repeating: "a", count: 1024)
        #expect(
            ToolSummary.header(for: try input(#"{"path":"b.txt","content":"\#(kb)"}"#), locale: Self.english)
                == "1 KiB (1,024 B) · b.txt"
        )
        #expect(
            ToolSummary.header(for: try input(#"{"path":"b.txt","content":"\#(kb)"}"#), locale: Self.german)
                == "1 KiB (1.024 B) · b.txt"
        )
        #expect(ToolSummary.fullInput(for: try input(#"{"path":"a.txt","content":"é\nhello"}"#)) == "é\nhello")
    }

    @Test func `an edit reads as the lines it removes and adds, between the lines it keeps (roadmap 0152)`() throws {
        let edit = try input(
            #"{"path":"a.swift","old_text":"let a = 1\nlet b = 2\nlet c = 3","new_text":"let a = 1\nlet b = 20\nlet c = 3\nlet d = 4"}"#
        )
        #expect(ToolSummary.fullInput(for: edit) == "  let a = 1\n- let b = 2\n+ let b = 20\n  let c = 3\n+ let d = 4")
        // Within a change, what goes comes before what replaces it, however the diff orders its edits.
        let swap = try input(#"{"path":"a","old_text":"a\nb\nkeep\nc","new_text":"x\ny\nkeep\nz"}"#)
        #expect(ToolSummary.fullInput(for: swap) == "- a\n- b\n+ x\n+ y\n  keep\n- c\n+ z")
        let removal = try input(#"{"path":"a","old_text":"gone\ntoo\n","new_text":""}"#)
        #expect(ToolSummary.fullInput(for: removal) == "- gone\n- too")
        // Lines the model wrote with a carriage return keep it out of the drawn line.
        let crlf = try input(#"{"path":"a","old_text":"a\r\nb","new_text":"a\r\nc"}"#)
        #expect(ToolSummary.fullInput(for: crlf) == "  a\n- b\n+ c")
    }

    @Test func `replacement and job inputs keep their distinct meanings`() throws {
        let edit = try input(#"{"path":"a","old_text":"before","new_text":"after"}"#)
        #expect(ToolSummary.fullInput(for: edit) == "- before\n+ after")
        #expect(ToolSummary.header(for: edit) == "exact replacement · a")
        #expect(ToolSummary.header(for: try input(##"{"job":"#abcd","action":"stop"}"##)) == "stop · #abcd")
        #expect(ToolSummary.header(for: try input(#"{"job":"job-3"}"#)) == "input · job-3")
        #expect(ToolSummary.header(for: try input(#"{"path":"a","limit":1}"#)) == "line 1 · a", "one line is one line")
    }

    /// IEC units past KiB, one decimal at most, with the exact count beside them (roadmap 0078).
    @Test func `sizes use the largest IEC unit that keeps a number at least one`() {
        #expect(ToolSummary.formatBytes(1023, locale: Self.english) == "1023 B")
        #expect(ToolSummary.formatBytes(1536, locale: Self.english) == "1.5 KiB (1,536 B)")
        // Rounded to one decimal, 1,048,575 B is 1024.0 KiB: the unit is chosen after rounding.
        #expect(ToolSummary.formatBytes(1_048_575, locale: Self.english) == "1 MiB (1,048,575 B)")
        #expect(ToolSummary.formatBytes(1_000_000, locale: Self.english) == "976.6 KiB (1,000,000 B)")
        #expect(ToolSummary.formatBytes(1_048_576, locale: Self.english) == "1 MiB (1,048,576 B)")
        #expect(ToolSummary.formatBytes(3_250_586, locale: Self.english) == "3.1 MiB (3,250,586 B)")
        #expect(ToolSummary.formatBytes(5 << 30, locale: Self.english) == "5 GiB (5,368,709,120 B)")
    }

    /// The decimal mark and the thousands separator are the locale's, injected here and `.current` on screen (roadmap 0078).
    @Test func `sizes are written in the locale's numbers`() {
        #expect(ToolSummary.formatBytes(1536, locale: Self.german) == "1,5 KiB (1.536 B)")
        #expect(ToolSummary.formatBytes(5 << 30, locale: Self.german) == "5 GiB (5.368.709.120 B)")
        #expect(ToolSummary.formatBytes(1023, locale: Self.german) == "1023 B")
    }

    /// An MCP server's or another unknown tool's input reads as labelled lines, never JSON (note n68): keys as words in the model's
    /// order, nested values indented under their label, lists of words joined, yes and no, empty values left out.
    @Test func `unknown tools show their input as labelled lines in its own order`() throws {
        let json = try input(#"{"zeta":"z\"q","nested":{"b":1,"a":[2,3]},"empty":{},"flag":true}"#)
        #expect(ToolSummary.fullInput(for: json) == "Zeta: z\"q\nNested:\n  B: 1\n  A: 2, 3\nFlag: yes")
    }

    /// A multi-line string is the text a person reads: shown as written, indented under its label, where it stands.
    @Test func `an unknown tool's multi-line strings are shown as their text, in order`() throws {
        let json = try input(#"{"title":"one line","body":"first\n\tsecond \"quoted\"","n":2,"tail":"a\nb"}"#)
        #expect(
            ToolSummary.fullInput(for: json)
                == "Title: one line\nBody:\n  first\n  \tsecond \"quoted\"\nN: 2\nTail:\n  a\n  b"
        )
        #expect(ToolSummary.fullInput(for: try input(#"{"sql":"select 1\nfrom t"}"#)) == "Sql:\n  select 1\n  from t")
        #expect(ToolSummary.fullInput(for: try input(#"{"o":{"s":"a\nb"}}"#)) == "O:\n  S:\n    a\n    b")
    }

    /// When the one-line header says everything, the block has no details; a list is counted on the header and listed below.
    @Test func `a call the header says in full has no details, and a list is counted then listed`() throws {
        let query = try input(#"{"query":"foo","limit":5}"#)
        #expect(ToolSummary.header(for: query) == "query foo · limit 5")
        #expect(ToolSummary.fullInput(for: query).isEmpty)
        let changes = try input(#"{"changes":[{"op":"add","title":"x"},{"op":"state","ids":"t1"}]}"#)
        #expect(ToolSummary.header(for: changes) == "2 changes")
        #expect(ToolSummary.fullInput(for: changes) == "Changes:\n  - op add · title x\n  - op state · ids t1")
        #expect(!ToolSummary.header(for: changes).contains("{") && !ToolSummary.fullInput(for: changes).contains("{"))
    }

    /// The one line is never empty when the call says something (note n70): a record's fields go in parentheses after its name.
    @Test func `a call whose input is records reads them on the header`() throws {
        #expect(ToolSummary.header(for: try input(#"{"read":{"view":"new"}}"#)) == "read (view new)")
        #expect(
            ToolSummary.header(for: try input(#"{"read":{"ids":"t5 t228","view":"all"}}"#))
                == "read (ids t5 t228 · view all)"
        )
        #expect(
            ToolSummary.header(
                for: try input(#"{"changes":[{"ids":"n70","state":"acknowledged"}],"read":{"view":"new"}}"#)
            )
                == "1 changes · read (view new)"
        )
        #expect(ToolSummary.header(for: try input(#"{"read":{}}"#)) == "read")
        #expect(ToolSummary.header(for: try input(#"{}"#)).isEmpty)
    }
}
