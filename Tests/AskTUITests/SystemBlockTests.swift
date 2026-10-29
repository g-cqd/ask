internal import TerminalKitStyle
internal import TerminalKitText
internal import Testing

@testable import AskTUI

/// ask's own messages are blocks tinted purple, whole; errors stay red and untinted; `ui.tint: off` turns it off with the rest (roadmap 0106).
@Suite("ask's own blocks are purple")
struct SystemBlockTests {
    private func rows(_ items: [ConversationUpdate], tint: Bool = true, columns: Int = 40) -> [ScreenComposer.Line] {
        var controller = ScreenController(label: "m", options: ScreenOptions(tint: tint))
        for item in items { controller.handle(item) }
        return (0 ..< controller.state.transcript.items.count)
            .flatMap {
                ScreenComposer.lines(
                    in: controller.state.transcript, at: $0, columns: columns, style: controller.state.blocks)
            }
    }

    @Test func `a notice is tinted purple on every row of its block, padding included`() {
        let theme = ScreenTheme()
        let lines = rows([.notice("Configuration reloaded.", isError: false)])
        #expect(lines.count == 3, "padding, the message, padding")
        #expect(lines.allSatisfy { $0.style.bg == theme.system })
        #expect(theme.system != .default)
    }

    @Test func `an error stays untinted and red, and tint off tints nothing`() {
        let error = rows([.notice("ask: it broke", isError: true)])
        #expect(error.allSatisfy { $0.style.bg == .default } && error.contains { $0.style.fg == .indexed(1) })
        #expect(rows([.notice("fine", isError: false)], tint: false).allSatisfy { $0.style.bg == .default })
    }

    @Test func `two of ask's blocks in a row are set apart by a blank row, as tool blocks are`() {
        let lines = rows([.notice("one", isError: false), .notice("two", isError: false)])
        let one = lines.firstIndex { $0.text.contains("one") }!
        let two = lines.firstIndex { $0.text.contains("two") }!
        let between = lines[(one + 1) ..< two]
        #expect(
            between.contains { $0.text.isEmpty && $0.style.bg == .default },
            "an untinted row sits between the two purple blocks")
    }

    /// How far the red channel sits above the green one, against the page: purple pulls red up, blue pulls it down.
    private func warmth(_ color: Color, page: ScreenTheme.Page) -> Double {
        guard case .rgb(let r, let g, _) = color else { return 0 }
        return (Double(r) - Double(g)) - (page.background.x - page.background.y)
    }

    @Test func `purple is a different hue from the user's blue on light and dark pages`() {
        for page: ScreenTheme.Page in [
            .light, .dark, .init(background: SIMD3(0, 43, 54), foreground: SIMD3(131, 148, 150))
        ] {
            let theme = ScreenTheme(page: page)
            #expect(
                warmth(theme.system, page: page) - warmth(theme.user, page: page) >= 15,
                "\(page): purple \(warmth(theme.system, page: page)), blue \(warmth(theme.user, page: page))")
        }
    }
}
