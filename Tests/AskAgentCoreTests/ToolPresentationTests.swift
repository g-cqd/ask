import AemiJSON
import AskAI
import Testing

@testable import AskAgentCore

@Suite("Tool presentation preserves full input and separates target from parameters")
struct ToolPresentationTests {
    private func input(_ json: String) throws -> JSONObject { try JSONObject(validating: Array(json.utf8)) }

    @Test func `complete multiline shell commands are not reduced to the header`() throws {
        let command = String(repeating: "x", count: 200) + "\nsecond line"
        let json = try input(
            #"{"command":"\#(String(repeating: "x", count: 200))\nsecond line","timeout_seconds":60,"yield_seconds":5}"#
        )
        #expect(ToolSummary.fullInput(for: json) == command)
        #expect(ToolSummary.header(for: json).contains(" · timeout 60s · yield 5s"))
        #expect(!ToolSummary.header(for: json).contains("second line"))
    }

    @Test func `read and write headers show concise window and size parameters`() throws {
        #expect(
            ToolSummary.header(for: try input(#"{"path":"src/a.swift","offset":10,"limit":36}"#))
                == "src/a.swift · [10:45]")
        #expect(
            ToolSummary.header(for: try input(#"{"path":"src/b.swift","offset":15}"#))
                == "src/b.swift · [15:]")
        #expect(ToolSummary.header(for: try input(#"{"path":"a.txt","content":"é"}"#)) == "a.txt · 2 B")
        let kb = String(repeating: "a", count: 1024)
        #expect(
            ToolSummary.header(for: try input(#"{"path":"b.txt","content":"\#(kb)"}"#)) == "b.txt · 1 KiB (1,024 B)")
        #expect(ToolSummary.fullInput(for: try input(#"{"path":"a.txt","content":"é\nhello"}"#)) == "é\nhello")
    }

    @Test func `replacement and job inputs keep their distinct meanings`() throws {
        let edit = try input(#"{"path":"a","old_text":"before","new_text":"after"}"#)
        #expect(ToolSummary.fullInput(for: edit) == "old_text:\nbefore\nnew_text:\nafter")
        #expect(ToolSummary.header(for: edit) == "a · exact replacement")
        #expect(ToolSummary.header(for: try input(##"{"job":"#abcd","action":"stop"}"##)) == "#abcd · stop")
    }

    /// IEC units past KiB, one decimal at most, with the exact count beside them (roadmap 0078).
    @Test func `sizes use the largest IEC unit that keeps a number at least one`() {
        #expect(ToolSummary.formatBytes(1023) == "1023 B")
        #expect(ToolSummary.formatBytes(1536) == "1.5 KiB (1,536 B)")
        // Rounded to one decimal, 1,048,575 B is 1024.0 KiB: the unit is chosen after rounding.
        #expect(ToolSummary.formatBytes(1_048_575) == "1 MiB (1,048,575 B)")
        #expect(ToolSummary.formatBytes(1_000_000) == "976.6 KiB (1,000,000 B)")
        #expect(ToolSummary.formatBytes(1_048_576) == "1 MiB (1,048,576 B)")
        #expect(ToolSummary.formatBytes(3_250_586) == "3.1 MiB (3,250,586 B)")
        #expect(ToolSummary.formatBytes(5 << 30) == "5 GiB (5,368,709,120 B)")
    }

    /// An MCP server's or another unknown tool's input is shown as indented JSON, keys in the model's order (roadmap 0078).
    @Test func `unknown tools show their input as indented JSON in its own order`() throws {
        let json = try input(#"{"zeta":"z\"q","nested":{"b":1,"a":[2,3]},"empty":{},"flag":true}"#)
        let shown = ToolSummary.fullInput(for: json)
        #expect(
            shown == """
                {
                  "zeta": "z\\"q",
                  "nested": {
                    "b": 1,
                    "a": [
                      2,
                      3
                    ]
                  },
                  "empty": {},
                  "flag": true
                }
                """)
        // Still the same JSON: what is shown parses back to the input's value.
        #expect(try JSONValue(AemiJSON.parse(Array(shown.utf8)).root) == JSONValue(AemiJSON.parse(json.bytes).root))
    }
}
