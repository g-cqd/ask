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

    @Test func `unknown tools retain every input byte`() throws {
        let json = try input(#"{"nested":{"a":1},"values":[2,3]}"#)
        #expect(ToolSummary.fullInput(for: json) == String(decoding: json.bytes, as: UTF8.self))
    }
}
