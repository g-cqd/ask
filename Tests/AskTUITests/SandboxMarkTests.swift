internal import TerminalKitStyle
internal import TerminalKitText
internal import Testing

@testable import AskTUI

/// The first status component says whether the sandbox is on: a green check, or `!` when it is off; a click names it for five seconds
/// (roadmap 0133).
@Suite("The sandbox mark")
struct SandboxMarkTests {
    private func rig(sandboxed: Bool) -> PointerRig {
        var rig = PointerRig(columns: 60, rows: 12, options: ScreenOptions(), updates: [.sandboxActive(sandboxed)])
        rig.draw()
        return rig
    }

    private func status(_ rig: PointerRig) -> ScreenComposer.Line {
        ScreenComposer.status(for: rig.controller.state, columns: 60).line
    }

    @Test func `idle, the mark is a green check with the sandbox on and a warning ! with it off`() {
        let on = status(rig(sandboxed: true))
        #expect(on.text.hasPrefix("✓ · ") && on.accents.first?.style == StatusLeadingMark.protected)
        #expect(StatusLeadingMark.protected.fg == .indexed(2))
        let off = status(rig(sandboxed: false))
        #expect(off.text.hasPrefix("! · ") && off.accents.first?.style == StatusLeadingMark.warning)
    }

    @Test func `a click on the mark names the state in the same colour, and five seconds later it is the mark again`()
        throws
    {
        for (sandboxed, word, mark, style) in [
            (true, "Sandboxed", "✓", StatusLeadingMark.protected),
            (false, "Not sandboxed", "!", StatusLeadingMark.warning)
        ] {
            var rig = rig(sandboxed: sandboxed)
            let row = rig.controller.frame.statusRow
            let effects = rig.click(row: row, col: 0)
            guard case .armSandboxNoteTimer(let generation) = try #require(effects.first) else {
                Issue.record("a click arms the timer")
                return
            }
            rig.draw()
            let line = status(rig)
            #expect(line.text.hasPrefix(word + " · "), "\(sandboxed): \(line.text)")
            #expect(line.accents.first?.style == style)
            #expect(line.accents.first?.columns == 0 ..< UnicodeWidth.displayWidth(of: word))
            rig.controller.sandboxNoteEnded(generation: generation + 1)
            #expect(status(rig).text.hasPrefix(word + " · "), "a timer from another click does not end this one")
            rig.controller.sandboxNoteEnded(generation: generation)
            rig.draw()
            #expect(status(rig).text.hasPrefix(mark + " · "))
        }
    }

    @Test func `a second click closes it at once, and the first timer then means nothing`() throws {
        var rig = rig(sandboxed: true)
        let row = rig.controller.frame.statusRow
        guard case .armSandboxNoteTimer(let first) = try #require(rig.click(row: row, col: 0).first) else { return }
        rig.draw()
        _ = rig.click(row: row, col: 0, after: .seconds(1))
        rig.draw()
        #expect(status(rig).text.hasPrefix("✓ · "))
        guard
            case .armSandboxNoteTimer(let second) = try #require(rig.click(row: row, col: 0, after: .seconds(2)).first)
        else {
            return
        }
        rig.controller.sandboxNoteEnded(generation: first)
        rig.draw()
        #expect(status(rig).text.hasPrefix("Sandboxed · "), "an old timer does not end a newer note")
        #expect(second > first)
    }

    @Test func `the mark is a click target only while it is the mark: not under a spinner, not off its columns`() {
        var rig = rig(sandboxed: true)
        let row = rig.controller.frame.statusRow
        #expect(rig.controller.frame.markColumns == 0 ..< 1)
        #expect(rig.click(row: row, col: 3).isEmpty, "the label next to it is not a target")
        rig.controller.handle(.userPrompt("go"))
        _ = rig.controller.begin(.startRun("go"))
        rig.draw()
        #expect(rig.controller.frame.markColumns == nil)
        #expect(rig.click(row: row, col: 0).isEmpty)
    }
}
