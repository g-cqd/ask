import TerminalKitStyle
import TerminalKitText
internal import Testing

@testable import AskTUI

/// A running block's header shimmers (roadmaps 0171 and 0187): the header faint, a bold stretch with softer edges gliding along it with
/// time, and nothing when the block ends or `ui.shimmer` is off.
@Suite("A running block's header shimmers")
struct ShimmerTests {
    private func transcript(shimmer: Bool = true, after elapsed: Duration, finished: Bool = false) -> Transcript {
        var transcript = Transcript()
        transcript.shimmer = shimmer
        transcript.startTool(name: "shell", summary: "swift build --configuration release", id: "c")
        if let started = transcript.progress[0]?.started {
            transcript.progress[0]?.sampled = started.advanced(by: elapsed)
        }
        if finished { transcript.finishTool(.succeeded, output: "ok", id: "c") }
        return transcript
    }

    private func header(_ transcript: Transcript) -> ScreenComposer.Line? {
        ScreenComposer.lines(in: transcript, at: 0, columns: 80, style: BlockStyle()).first { $0.source?.line == 0 }
    }

    @Test func `the header is faint, and the stretch is a bold core with softer edges`() throws {
        let theme = BlockStyle().theme
        let line = try #require(header(transcript(after: .seconds(1))))
        #expect(
            line.style.fg == theme.shimmerBase && line.style.dim,
            "fainter than dim: dim, and a colour toward the page"
        )
        #expect(line.accents.count == 3)
        let edges = [line.accents[0], line.accents[2]]
        #expect(edges.allSatisfy { $0.columns.count == 1 && $0.style.fg == theme.shimmerEdge && !$0.style.bold })
        #expect(line.accents[1].columns.count == ScreenComposer.shimmerCore && line.accents[1].style.bold)
        #expect(!line.accents[1].style.dim && line.accents[1].style.fg != theme.shimmerBase)
    }

    @Test func `it glides a column every 50 ms, whatever the spinner does`() throws {
        let at = try #require(header(transcript(after: .milliseconds(1_000)))?.accents.first?.columns.lowerBound)
        let later = try #require(header(transcript(after: .milliseconds(1_050)))?.accents.first?.columns.lowerBound)
        #expect(later == at + 1)
    }

    @Test func `it stays inside the header's text, entering and leaving at its ends`() throws {
        let text = try #require(header(transcript(after: .zero))?.source)
        let width = UnicodeWidth.displayWidth(of: text.text)
        for step in 0 ..< 120 {
            for accent in try #require(header(transcript(after: .milliseconds(step * 37)))).accents {
                #expect(accent.columns.lowerBound >= text.col && accent.columns.upperBound <= text.col + width)
            }
        }
    }

    @Test func `a finished block, or ui.shimmer off, stays still and keeps its own look`() throws {
        let finished = try #require(header(transcript(after: .seconds(1), finished: true)))
        #expect(finished.accents.isEmpty && finished.style.fg != BlockStyle().theme.shimmerBase)
        #expect(header(transcript(shimmer: false, after: .seconds(1)))?.accents.isEmpty == true)
    }

    @Test func `a tick between frames redraws the shimmer and leaves the spinner where it was`() {
        var transcript = transcript(after: .zero)
        transcript.advanceProgress(advancingFrames: false)
        #expect(transcript.progress[0]?.frame == 0)
        transcript.advanceProgress(advancingFrames: true)
        #expect(transcript.progress[0]?.frame == 1)
    }

    @Test(arguments: [BlockProgressTimer.shimmerInterval, BlockProgressTimer.frameInterval])
    func `spinners step every 200 ms on average, whatever the tick`(tick: Duration) {
        var since = Duration.zero
        var frames = 0
        var elapsed = Duration.zero
        while elapsed < .seconds(3) {
            elapsed += tick
            if BlockProgressTimer.advances(&since, after: tick) { frames += 1 }
        }
        #expect(frames == 15)
    }

    @Test func `the star and dot spinners are gone`() {
        #expect(SpinnerStyle(rawValue: "star") == nil && SpinnerStyle(rawValue: "dot") == nil)
        #expect(!SpinnerStyle.allConcrete.contains { $0.frames.contains("✶") || $0.frames.contains("•") })
    }
}
