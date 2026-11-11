internal import Testing

@testable import AskTUI

/// The folder ask works in, on the status line (notes n6 and n63; the owner's answers of 2026-11-11): on by default as its last
/// folder, right after the mark; `ui.statusPath` chooses the form or turns it off, `ui.statusPathSide` the end it sits at. When the
/// line is narrow it shortens to the last folder, then goes, before the context's use and the model's name.
@Suite("The status line says which folder ask works in")
struct StatusPathTests {
    private func state(_ form: StatusPathForm = .folder, side: StatusPathSide = .leading) -> ScreenState {
        var options = ScreenOptions()
        options.workspace = "/Users/me/src/shop"
        options.home = "/Users/me"
        options.statusPath = form
        options.statusPathSide = side
        var state = ScreenState(label: "claude-5", options: options)
        state.context = "12%"
        return state
    }

    private func text(_ state: ScreenState, columns: Int = 200) -> String {
        ScreenComposer.status(for: state, columns: columns).line.text
    }

    @Test func `by default the last folder, right after the mark`() {
        let mark = ScreenComposer.leadingMark(for: state()).character
        #expect(text(state()) == "\(mark) · shop · claude-5 · 12%")
        #expect(ScreenOptions().statusPath == .folder && ScreenOptions().statusPathSide == .leading)
    }

    @Test func `the forms: from home, in full, or none`() {
        let mark = ScreenComposer.leadingMark(for: state()).character
        #expect(text(state(.home)) == "\(mark) · ~/src/shop · claude-5 · 12%")
        #expect(text(state(.full)) == "\(mark) · /Users/me/src/shop · claude-5 · 12%")
        #expect(text(state(.off)) == "\(mark) · claude-5 · 12%")
    }

    @Test func `at the trailing end`() {
        let mark = ScreenComposer.leadingMark(for: state()).character
        #expect(text(state(side: .trailing)) == "\(mark) · claude-5 · 12% · shop")
    }

    @Test func `narrow, it shortens to the last folder, then goes before the context's use`() {
        let mark = ScreenComposer.leadingMark(for: state()).character
        let full = state(.full)
        let short = "\(mark) · shop · claude-5 · 12%"
        #expect(text(full, columns: short.count) == short)
        #expect(text(full, columns: short.count - 1) == "\(mark) · claude-5 · 12%")
    }

    @Test func `with no folder known, the line is as before`() {
        let plain = ScreenState(label: "claude-5")
        let mark = ScreenComposer.leadingMark(for: plain).character
        #expect(text(plain) == "\(mark) · claude-5")
    }
}
