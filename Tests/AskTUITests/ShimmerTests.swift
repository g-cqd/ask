import TerminalKitStyle
import TerminalKitText
internal import Testing

@testable import AskTUI

/// A running block's header shimmers (roadmap 0171): a brighter stretch moves along it with the spinner, and stops with it.
@Suite("A running block's header shimmers")
struct ShimmerTests {
    private func transcript(shimmer: Bool = true, frame: Int, finished: Bool = false) -> Transcript {
        var transcript = Transcript()
        transcript.shimmer = shimmer
        transcript.startTool(name: "shell", summary: "swift build", id: "c")
        transcript.progress[0]?.frame = frame
        if finished { transcript.finishTool(.succeeded, output: "ok", id: "c") }
        return transcript
    }

    private func header(_ transcript: Transcript) -> ScreenComposer.Line? {
        ScreenComposer.lines(in: transcript, at: 0, columns: 60, style: BlockStyle()).first { $0.source?.line == 0 }
    }

    @Test func `a stretch of the running header is drawn brighter, and it moves with the spinner`() throws {
        let first = try #require(header(transcript(frame: 3)))
        let accent = try #require(first.accents.first)
        #expect(accent.columns.count == ScreenComposer.shimmerWidth)
        #expect(first.style.dim && !accent.style.dim, "the running header is dim; the stretch is not")
        let next = try #require(header(transcript(frame: 4))?.accents.first)
        #expect(next.columns.lowerBound == accent.columns.lowerBound + 2)
    }

    @Test func `it stays inside the header's text, entering and leaving at its ends`() throws {
        let text = try #require(header(transcript(frame: 0))?.source)
        let width = UnicodeWidth.displayWidth(of: text.text)
        for frame in 0 ..< 40 {
            for accent in try #require(header(transcript(frame: frame))).accents {
                #expect(accent.columns.lowerBound >= text.col && accent.columns.upperBound <= text.col + width)
            }
        }
    }

    @Test func `a finished block, or ui.shimmer off, stays still`() {
        #expect(header(transcript(frame: 3, finished: true))?.accents.isEmpty == true)
        #expect(header(transcript(shimmer: false, frame: 3))?.accents.isEmpty == true)
    }

    @Test func `the star and dot spinners are gone`() {
        #expect(SpinnerStyle(rawValue: "star") == nil && SpinnerStyle(rawValue: "dot") == nil)
        #expect(!SpinnerStyle.allConcrete.contains { $0.frames.contains("✶") || $0.frames.contains("•") })
    }
}
