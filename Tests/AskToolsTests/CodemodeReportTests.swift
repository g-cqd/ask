import AskCodemode
import Testing

@testable import AskTools

/// What the model reads of a script (ADR-0156, pi's format on purpose): whether it completed, how long it took, what it said.
@Suite("A script's result says how it ended, then what it said")
struct CodemodeReportTests {
    private func items(_ texts: String...) -> [CodemodeItem] { texts.map { CodemodeItem(text: $0) } }

    @Test func `one text is said as it is, under how the script ended`() {
        let report = CodemodeReport.text(CodemodeResult(items: items("42")), took: .milliseconds(412))
        #expect(report == "Script completed in 0.41 s.\n42")
    }

    @Test func `several texts are each headed, in order`() {
        let report = CodemodeReport.text(CodemodeResult(items: items("first", "second\nline")), took: .seconds(2))
        #expect(report == "Script completed in 2.00 s.\n==> text 1/2 <==\nfirst\n==> text 2/2 <==\nsecond\nline")
    }

    @Test func `console lines follow the text, in a block of their own`() {
        let said = [
            CodemodeItem(text: "log a", console: true), CodemodeItem(text: "the answer"),
            CodemodeItem(text: "log b", console: true)
        ]
        let report = CodemodeReport.text(CodemodeResult(items: said), took: .milliseconds(10))
        #expect(report == "Script completed in 0.01 s.\nthe answer\n<console_output>\nlog a\nlog b\n</console_output>")
    }

    @Test func `a script that said nothing says so`() {
        #expect(
            CodemodeReport.text(CodemodeResult(), took: .milliseconds(5)) == "Script completed in 0.01 s.\n(no output)"
        )
    }

    @Test func `a failure says why first, and keeps what the script had said`() {
        let result = CodemodeResult(items: items("partial"), failure: "Error: no such file (codemode.js:3)")
        let report = CodemodeReport.text(result, took: .milliseconds(80))
        #expect(report == "Script failed after 0.08 s: Error: no such file (codemode.js:3)\npartial")
        #expect(CodemodeReport.text(CodemodeResult(failure: "why"), took: .zero) == "Script failed after 0.00 s: why")
    }

    @Test func `calls still running at the end are said to have been cancelled`() {
        let report = CodemodeReport.text(CodemodeResult(items: items("ok"), unsettled: 2), took: .seconds(1))
        #expect(
            report
                == "Script completed in 1.00 s.\nok\n[2 tool calls were still running when the script ended, and were cancelled.]"
        )
        let one = CodemodeReport.text(CodemodeResult(unsettled: 1), took: .seconds(1))
        #expect(one.hasSuffix("[1 tool call was still running when the script ended, and was cancelled.]"))
    }

    @Test func `a result past its tokens keeps its start and its end, and says where the whole is`() {
        let long = (1 ... 400).map { "line \($0) of the output" }.joined(separator: "\n")
        let report = CodemodeReport.text(CodemodeResult(items: items(long)), took: .seconds(1))
        let cut = CodemodeReport.fitted(report, tokens: 100, whole: "/tmp/out/codemode-t1.txt")
        #expect(cut.utf8.count < 700)
        #expect(cut.hasPrefix("Script completed in 1.00 s.\nline 1 of the output\n"))
        #expect(cut.contains("lines omitted"))
        #expect(cut.hasSuffix("line 400 of the output\n[The whole output is in /tmp/out/codemode-t1.txt.]"))
        #expect(CodemodeReport.fitted(report, tokens: 100, whole: nil).hasSuffix("line 400 of the output"))
        #expect(CodemodeReport.fitted("short", tokens: 100, whole: "/x") == "short", "what fits is not touched")
    }
}
