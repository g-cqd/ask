internal import TerminalKitStyle
internal import Testing

@testable import AskTUI

/// A row is cut into runs, each in the style it is drawn in: the row's own, an accent over it, the selection as inverse over both, and the row's
/// background under every run (roadmap 0074: a tinted row is tinted to the edge).
@Suite("A row is drawn in runs: its style, its accents, and the selection over both")
struct RowSpansTests {
    private let warning = Style(fg: .indexed(3))

    @Test func `a plain row is one run`() {
        let spans = ScreenComposer.spans(of: .init(text: "hello", style: .default), highlight: nil)
        #expect(spans.count == 1 && spans[0].0 == "hello")
    }

    @Test func `an accent is its own run in its own style, and the rest keeps the row's`() {
        let line = ScreenComposer.Line(
            text: "⚠ codex", style: Style(dim: true), accents: [.init(columns: 0 ..< 1, style: warning)])
        let spans = ScreenComposer.spans(of: line, highlight: nil)
        #expect(spans.map(\.0) == ["⚠", " codex"])
        #expect(spans[0].1 == warning && spans[1].1 == Style(dim: true))
    }

    @Test func `the selection is inverse over an accent, and nothing else changes`() {
        let line = ScreenComposer.Line(
            text: "abcdef", style: .default, accents: [.init(columns: 2 ..< 4, style: warning)])
        let spans = ScreenComposer.spans(of: line, highlight: 3 ..< 5)
        #expect(spans.map(\.0) == ["ab", "c", "d", "e", "f"])
        #expect(spans.map(\.1.inverse) == [false, false, true, true, false])
        #expect(spans[1].1.fg == warning.fg && spans[2].1.fg == warning.fg)
    }

    @Test func `an accent without a background takes the row's, so a tinted row stays tinted under it`() {
        let tint = Color.rgb(r: 40, g: 40, b: 50)
        let line = ScreenComposer.Line(
            text: "⚠ x", style: Style(bg: tint), accents: [.init(columns: 0 ..< 1, style: warning)])
        #expect(ScreenComposer.spans(of: line, highlight: nil).allSatisfy { $0.1.bg == tint })
    }

    @Test func `an accent past the row's end is ignored`() {
        let line = ScreenComposer.Line(text: "ab", style: .default, accents: [.init(columns: 5 ..< 9, style: warning)])
        #expect(ScreenComposer.spans(of: line, highlight: nil).map(\.0) == ["ab"])
    }
}
