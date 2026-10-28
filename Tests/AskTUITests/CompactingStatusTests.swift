internal import TerminalKitStyle
internal import TerminalKitText
internal import Testing

@testable import AskTUI

/// While the conversation is compacted, the status bar's leading mark says so, in purple (roadmap 0099).
@Suite("The status bar says Compacting...")
struct CompactingStatusTests {
    @Test func `while compacting, the mark is the spinner, one space, and the word, all of it in purple`() throws {
        var controller = ScreenController(label: "model")
        controller.state.running = true
        controller.handle(.compacting(true))
        controller.state.statusFrame = 0
        let line = ScreenComposer.status(for: controller.state, columns: 80).line
        let frame = try #require(controller.state.transcript.spinnerStyle.frames.first)
        #expect(line.text.hasPrefix(frame + " Compacting... · model"))
        let accent = try #require(line.accents.first)
        #expect(accent.style == StatusLeadingMark.compacting && accent.style.fg == .indexed(5))
        #expect(accent.columns == 0 ..< UnicodeWidth.displayWidth(of: frame + " Compacting..."))
        #expect(controller.hasLiveProgress, "the spinner turns while compacting")
    }

    @Test func `the end of a compaction, or of the run, puts the usual mark back`() {
        var controller = ScreenController(label: "model")
        controller.state.running = true
        controller.handle(.compacting(true))
        controller.handle(.compacting(false))
        #expect(!ScreenComposer.status(for: controller.state, columns: 80).line.text.contains("Compacting"))
        controller.handle(.compacting(true))
        controller.handle(.runEnded)
        #expect(!controller.state.compacting)
        #expect(!ScreenComposer.status(for: controller.state, columns: 80).line.text.contains("Compacting"))
    }

    @Test func `a narrow status keeps the whole word or drops the label, never cuts the mark's colour short`() {
        var controller = ScreenController(label: "a-long-model-name")
        controller.state.running = true
        controller.handle(.compacting(true))
        let line = ScreenComposer.status(for: controller.state, columns: 12).line
        #expect(line.accents.allSatisfy { $0.columns.upperBound <= UnicodeWidth.displayWidth(of: line.text) })
    }
}
