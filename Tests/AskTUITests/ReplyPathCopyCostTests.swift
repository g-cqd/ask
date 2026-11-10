internal import Foundation
internal import TerminalKitText
internal import Testing

@testable import AskTUI

/// A reproducible release measurement, not a timing assertion: the old source copy and the path-aware copy have different output.
/// Run with `swift test -c release --enable-testable-imports --filter ReplyPathCopyCostTests`.
@Suite("Measure the added work of expanding copied reply paths")
struct ReplyPathCopyCostTests {
    @Test func `report interleaved source-copy and resolved-copy costs`() {
        let text =
            "Fixed Sources/a.swift:12, with notes about the change. " + String(repeating: "More prose. ", count: 20)
        var transcript = Transcript()
        transcript.setMarkdown(true)
        transcript.addAssistantText(text)
        let selection = ContentSelection(
            anchor: ContentPosition(block: 0, line: 0, offset: 0),
            head: ContentPosition(block: 0, line: 0, offset: text.count)
        )
        let display = PathDisplay(workspace: "/work/project", home: "/Users/me", ancestors: 2) { _ in true }
        let expected = text.replacing("Sources/a.swift", with: "/work/project/Sources/a.swift")
        var samples = [[Double]](repeating: [], count: 2)
        var correct = true
        for run in 0 ..< 9 {
            for mode in run.isMultiple(of: 2) ? [0, 1] : [1, 0] {
                let elapsed = ContinuousClock()
                    .measure {
                        for _ in 0 ..< 100 {
                            let copied =
                                mode == 0
                                ? selection.text(in: TranscriptContent(transcript))
                                : ReplyPathCopy.text(selection, in: transcript, display: display)
                            correct = correct && copied == (mode == 0 ? text : expected)
                        }
                    }
                let parts = elapsed.components
                let microseconds = Double(parts.seconds) * 1e6 + Double(parts.attoseconds) / 1e12
                samples[mode].append(microseconds / 100)
            }
        }
        #expect(correct)
        for mode in 0 ..< 2 {
            let values = samples[mode].sorted()
            print(
                "reply-copy \(mode == 0 ? "source" : "resolved"): median \(values[4]) us; range \(values[0])..\(values[8]); 9 x 100"
            )
        }
    }
}
