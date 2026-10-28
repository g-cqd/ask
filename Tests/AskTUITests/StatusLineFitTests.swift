internal import Foundation
internal import TerminalKitStyle
internal import Testing

@testable import AskTUI

/// The status line at every width (roadmap 0074): each piece whole, in a shorter form, or gone; never cut in the middle.
@Suite("The status line fits any width without cutting a piece")
struct StatusLineFitTests {
    @Test func `context is a whole segment retained ahead of cumulative usage`() {
        var state = ScreenState(label: "model")
        state.context = "25%/200k"
        state.detail = "↑12.3k ↓456"
        #expect(text(state, columns: 80) == "! · model · 25%/200k · ↑12.3k ↓456")
        #expect(text(state, columns: 20) == "! · model · 25%/200k")
    }

    @Test func `the ASCII warning is accented and separated from the model`() {
        var state = ScreenState(label: "codex/model")
        state.sandboxed = false
        let line = ScreenComposer.status(for: state, columns: 80).line
        #expect(line.text == "! · codex/model")
        #expect(line.accents.first?.columns == 0 ..< 1)
        #expect(line.accents.first?.style.fg == StatusLeadingMark.warning.fg)
    }

    @Test func `running sandboxed status starts with a spinner in the text colour and no working text`() {
        var state = ScreenState(label: "model")
        state.running = true
        state.sandboxed = true
        state.transcript.spinnerStyle = .braille
        state.statusFrame = 0
        let line = ScreenComposer.status(for: state, columns: 80).line
        #expect(line.text.hasPrefix("⠋ · model"))
        #expect(!line.text.contains("working"))
        #expect(line.accents.first?.columns == 0 ..< 1)
        #expect(line.accents.first?.style == StatusLeadingMark.sandboxed)
        #expect(StatusLeadingMark.sandboxed.fg == .default, "the terminal's text colour, readable on any page")
    }

    @Test func `running unsandboxed status starts with yellow spinner`() {
        var state = ScreenState(label: "model")
        state.running = true
        state.sandboxed = false
        state.transcript.spinnerStyle = .braille
        state.statusFrame = 1
        let line = ScreenComposer.status(for: state, columns: 80).line
        #expect(line.text.hasPrefix("⠙ · model"))
        #expect(line.accents.first?.style.fg == StatusLeadingMark.warning.fg)
    }

    @Test func `ongoing running jobs are positioned at the end of the line`() {
        var state = ScreenState(label: "model")
        state.running = true
        state.detail = "↑1k ↓2k"
        state.runners = [
            RunnerInfo(name: "job-1", detail: "sleep 10", id: "1", kind: .job, state: .running)
        ]
        let line = ScreenComposer.status(for: state, columns: 120).line
        #expect(line.text.hasSuffix("1 job"))
    }

    private func state(width _: Int = 0) -> ScreenState {
        var state = ScreenState(label: "codex/gpt-6.1-sol/medium")
        state.labelVariants = ["codex/gpt-6.1-sol/medium", "codex/gpt-6.1-sol", "gpt-6.1-sol"]
        state.detail = "↑12.3k ↓456"
        state.running = true
        state.scrollback = 12
        return state
    }

    private func text(_ state: ScreenState, columns: Int) -> String {
        ScreenComposer.status(for: state, columns: columns).line.text
    }

    @Test func `at a generous width everything is said, in order`() {
        #expect(
            text(state(), columns: 200)
                == "| · codex/gpt-6.1-sol/medium · ↑12.3k ↓456 · 12 lines below")
    }

    @Test func `there is no ready, and no sandbox word`() {
        var quiet = ScreenState(label: "codex/gpt-6.1-sol")
        quiet.labelVariants = []
        #expect(text(quiet, columns: 80) == "! · codex/gpt-6.1-sol")
    }

    @Test func `at no width does the line run past the screen`() {
        for columns in 8 ... 200 {
            let width = ScreenComposer.status(for: state(), columns: columns).line.text.count
            #expect(width <= columns, "\(columns) columns, the line is \(width)")
        }
    }

    @Test func `each piece that is shown is a whole one, at every width that fits the label`() {
        let wholes = [
            "codex/gpt-6.1-sol/medium", "codex/gpt-6.1-sol", "gpt-6.1-sol", "↑12.3k ↓456",
            "12 lines below"
        ]
        // 17 columns is the minimum width for the shortest label ("| · gpt-6.1-sol")
        for columns in 17 ... 200 {
            var raw = text(state(), columns: columns)
            if raw.hasPrefix("| · ") {
                raw = String(raw.dropFirst(4))
            }
            let pieces = raw.components(separatedBy: " · ")
            for piece in pieces { #expect(wholes.contains(piece), "\(columns) columns: \"\(piece)\" is a cut piece") }
        }
    }

    @Test
    func `the least important goes first: usage, then the count, and the label is shortened last`() {
        let full = "| · codex/gpt-6.1-sol/medium"
        #expect(text(state(), columns: 80) == full + " · ↑12.3k ↓456 · 12 lines below")
        #expect(text(state(), columns: 45) == full + " · 12 lines below")
        #expect(text(state(), columns: 35) == full)
        #expect(text(state(), columns: 25) == "| · codex/gpt-6.1-sol")
        #expect(text(state(), columns: 17) == "| · gpt-6.1-sol")
    }

    @Test func `a warning mark leads in colour, and only the mark`() {
        var s = state()
        s.sandboxed = false
        let line = ScreenComposer.status(for: s, columns: 80).line
        #expect(line.accents.count == 1 && line.accents[0].columns.lowerBound == 0)
        #expect(line.accents[0].style.fg == StatusLeadingMark.warning.fg)
        #expect(
            ScreenComposer.status(for: ScreenState(label: "codex/x"), columns: 80).line.accents.first?.style.fg
                == StatusLeadingMark.sandboxed.fg)
    }

    @Test func `a click's columns follow the shortening`() {
        let wide = ScreenComposer.status(for: state(), columns: 60)
        let narrow = ScreenComposer.status(for: state(), columns: 45)
        #expect(wide.below != nil && narrow.below != nil && wide.below != narrow.below)
        let line = narrow.line.text
        let below = narrow.below!
        #expect(String(line.dropFirst(below.lowerBound).prefix(below.count)) == "12 lines below")
    }

    @Test func `a question leads and is never given up for the label`() {
        var asking = state()
        asking.pendingInput = PendingInput(id: 1, prompt: "Paste the key:", secret: true)
        let line = text(asking, columns: 60)
        #expect(line.hasPrefix("Paste the key: › "))
    }

    @Test func `a copy that went wrong is said, and the native-selection hint only with verbose`() {
        var copied = ScreenState(label: "m")
        copied.clipboardNotice = "Terminal copy failed: x"
        copied.nativeSelectionHint = "Shift: native selection"
        #expect(text(copied, columns: 80) == "! · m · Terminal copy failed: x")
        copied.clipboardNotice = ""
        #expect(text(copied, columns: 80) == "! · m")
        copied.verbose = true
        #expect(text(copied, columns: 80) == "! · m · Shift: native selection")
    }
}
