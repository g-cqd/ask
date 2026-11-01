internal import Foundation
internal import Testing

@testable import AskTUI

/// Opt-in timing of a reply streaming in (roadmap 0152): the reply of ``MarkdownRenderBenchmark`` in 256-byte deltas, the message
/// composed after each as the screen does, highlighting on. Prints the mean compose of all frames and the median of the last 20,
/// which is what a long reply costs a delta once it is long.
/// `ASK_RENDER_BENCH=1 swift test -c release -Xswiftc -enable-testing --filter MarkdownStreamBenchmark`.
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["ASK_RENDER_BENCH"] != nil))
struct MarkdownStreamBenchmark {
    @Test func `times each frame of a long reply streaming in`() {
        let text = Array(MarkdownRenderBenchmark.reply().utf8)
        var report = "BENCH stream bytes \(text.count) delta 256"
        for folded in [true, false] {
            var best: (mean: Double, last: Double)?
            for _ in 0 ..< 5 {
                var transcript = Transcript()
                transcript.setMarkdown(true)
                transcript.setHighlight(true)
                if !folded { transcript.setCodeFoldedByDefault(false) }
                var frames: [Double] = []
                var start = 0
                while start < text.count {
                    let end = Swift.min(text.count, start + 256)
                    transcript.addAssistantText(String(decoding: text[start ..< end], as: UTF8.self))
                    start = end
                    let elapsed = ContinuousClock()
                        .measure {
                            _ = ScreenComposer.lines(in: transcript, at: 0, columns: MarkdownRenderBenchmark.columns)
                        }
                    frames.append(
                        Double(elapsed.components.seconds) * 1_000 + Double(elapsed.components.attoseconds) / 1e15
                    )
                }
                let mean = frames.reduce(0, +) / Double(frames.count)
                let last = frames.suffix(20).sorted()[10]
                if best == nil || mean < best!.mean { best = (mean, last) }
            }
            let name = folded ? "folded" : "open"
            report +=
                " \(name)-mean \((best!.mean * 1_000).rounded() / 1_000) \(name)-last \((best!.last * 1_000).rounded() / 1_000)"
        }
        print(report)
    }
}
