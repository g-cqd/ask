internal import AemiMarkdown
internal import Foundation
internal import TerminalKitMarkdown
internal import Testing

@testable import AskTUI

/// Opt-in timing of an assistant message's render path, step by step, in a release build (roadmap 0152):
/// `ASK_RENDER_BENCH=1 swift test -c release -Xswiftc -enable-testing --filter MarkdownRenderBenchmark`. This is the cost of a
/// message laid out cold (a new width, a new look); a streamed delta keeps the blocks before it (``MarkdownStreamBenchmark``).
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["ASK_RENDER_BENCH"] != nil))
struct MarkdownRenderBenchmark {
    static let columns = 120

    @Test func `times each step of rendering a reply with a long Swift block`() {
        let text = Self.reply()
        let document = MarkdownParser.parse(Array(text.utf8), extensions: ScreenComposer.markdownExtensions)
        let code = Self.codeLines(of: text)
        var report = "BENCH render bytes \(text.utf8.count) code-lines \(code.count) columns \(Self.columns)"
        report += Self.step("parse") {
            _ = MarkdownParser.parse(Array(text.utf8), extensions: ScreenComposer.markdownExtensions)
        }
        report += Self.step("hook") { _ = CodeHighlighter.standard.highlight(code, language: "swift") }
        for highlight in [false, true] {
            report += Self.step("renderer-\(highlight ? "on" : "off")") {
                var renderer = MarkdownRenderer(
                    theme: .standard, links: ScreenComposer.markdownLinks(home: "/home"),
                    highlighter: highlight ? CodeHighlighter.standard : nil, softBreaks: .lineBreak)
                for block in document.topLevelBlocks {
                    _ = renderer.lines(of: block, in: document, width: Self.columns)
                }
            }
            for folded in [true, false] {
                let name = "compose-\(highlight ? "on" : "off")-\(folded ? "folded" : "open")"
                // A fresh transcript each run, so the message is laid out cold, not taken from its rows kept the run before.
                report += Self.step(name) {
                    let transcript = Self.transcript(text, highlight: highlight, folded: folded)
                    _ = ScreenComposer.lines(in: transcript, at: 0, columns: Self.columns)
                }
            }
        }
        print(report)
    }

    /// ` name median ms`, of 20 timed runs after 3 to warm up.
    static func step(_ name: String, _ body: () -> Void) -> String {
        var samples: [Double] = []
        for iteration in 0 ..< 23 {
            let elapsed = ContinuousClock().measure(body)
            if iteration >= 3 {
                samples.append(
                    Double(elapsed.components.seconds) * 1_000 + Double(elapsed.components.attoseconds) / 1e15)
            }
        }
        let median = samples.sorted()[samples.count / 2]
        return " \(name) \((median * 1_000).rounded() / 1_000)"
    }

    static func transcript(_ text: String, highlight: Bool, folded: Bool) -> Transcript {
        var transcript = Transcript()
        transcript.setMarkdown(true)
        transcript.setHighlight(highlight)
        if !folded { transcript.setCodeFoldedByDefault(false) }
        transcript.addAssistantText(text)
        return transcript
    }

    /// About 39 KB: prose, lists and inline code around a 400-line Swift block, as a long reply that shows code is.
    static func reply() -> String {
        var prose = ""
        for index in 0 ..< 60 {
            prose += "The renderer lays out paragraph \(index) with `inline code`, **strong** and *emphasis* words, "
            prose +=
                "and a [link](https://example.com/\(index)) so that the wrapping has real work to do on every row.\n\n"
            if index % 10 == 9 {
                prose += "- one item with `code`\n- another item, longer, which wraps past the width\n\n"
            }
        }
        var code = "```swift\n"
        for index in 0 ..< 400 {
            switch index % 5 {
                case 0: code += "    /// Returns the \(index)th value, or nil when the cache holds none.\n"
                case 1: code += "    @inlinable public func value\(index)(at key: String) -> Int? { cache[key] }\n"
                case 2: code += "    let label\(index) = \"row \\(\(index)) of \\(count)\" // \(index * 3)\n"
                case 3: code += "    if count > 0x1F, let first = items.first { return first.id + \(index).5e-3 }\n"
                default: code += "    for item in items where item.isEnabled { total += item.weight * 2 }\n"
            }
        }
        code += "```\n"
        let half = prose.utf8.count / 2
        let split = prose.index(prose.startIndex, offsetBy: half)
        let cut = prose[split...].range(of: "\n\n").map(\.upperBound) ?? prose.endIndex
        return String(prose[..<cut]) + code + "\n" + String(prose[cut...])
    }

    /// The fenced block's lines, as the renderer hands them to the hook.
    static func codeLines(of text: String) -> [String] {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let open = lines.firstIndex(of: "```swift"), let close = lines[(open + 1)...].firstIndex(of: "```") else {
            return []
        }
        return Array(lines[(open + 1) ..< close])
    }
}
