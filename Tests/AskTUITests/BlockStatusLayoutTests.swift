internal import TerminalKitText
internal import Testing

@testable import AskTUI

@Suite("First-line block status")
struct BlockStatusLayoutTests {
    @Test func `status is on the first row and long content continues below at full width`() throws {
        let item = Transcript.Item.tool(
            name: "bash", summary: String(repeating: "x", count: 80), status: .succeeded, output: "a\nb")
        let rows = ScreenComposer.lines(for: item, folded: true, columns: 50)
        let first = try #require(rows.first)
        #expect(first.text.hasSuffix("00:00:00 · 2 lines · ✓"))
        #expect(UnicodeWidth.displayWidth(of: first.text) == 50)
        #expect(first.text.contains("xxxx    00:00:00"))
        #expect(rows.dropFirst().allSatisfy { !$0.text.contains("00:00:00") })
        #expect(rows.count > 1)
        #expect(UnicodeWidth.displayWidth(of: rows[1].text) == 50)
    }

    @Test func `failure codes are numeric and success omits the code`() {
        let failed = Transcript.Item.tool(name: "bash", summary: "false", status: .failed("[exit 7]"), output: "")
        let rows = ScreenComposer.lines(for: failed, columns: 60)
        #expect(rows.first?.text.hasSuffix("00:00:00 · ✗ (7)") == true)
        #expect(!rows.contains { $0.text.contains("[exit") })
    }
    @Test func `wide content and tiny widths keep source offsets and exclude metadata`() {
        let summary = String(repeating: "界é", count: 30)
        let item = Transcript.Item.tool(name: "read", summary: summary, status: .succeeded, output: "a")
        let rows = ScreenComposer.lines(for: item, folded: true, columns: 50)
        #expect(rows.allSatisfy { UnicodeWidth.displayWidth(of: $0.text) <= 50 })
        #expect(rows.compactMap { $0.source?.text }.joined() == "read " + summary)
        let ascii = Transcript.Item.tool(name: "bash", summary: "abc", status: .running, output: "")
        for width in 1 ... 30 {
            let tiny = ScreenComposer.lines(for: ascii, columns: width)
            #expect(tiny.allSatisfy { UnicodeWidth.displayWidth(of: $0.text) <= width })
            #expect(tiny.compactMap { $0.source?.text }.joined().filter { !$0.isWhitespace } == "bashabc")
            for source in tiny.compactMap(\.source) {
                #expect(String("bash abc".dropFirst(source.offset).prefix(source.text.count)) == source.text)
            }
        }
    }
}
