internal import Foundation
internal import TerminalKitCodecs
internal import TerminalKitStyle

/// The tints of the screen (roadmaps 0074 and 0108). A terminal has no alpha, so "a little off the page" is a colour mixed from the page itself:
/// the terminal's background, read with OSC 11, moved a few percent toward its foreground or a hue. A tint mixed from the real page keeps the
/// contrast the person chose for their terminal, light or dark, where fixed colours suit only the page they were picked on.
public struct ScreenTheme: Sendable, Equatable {
    /// Whether anything is tinted.
    public var tinted: Bool
    /// The page the tints were mixed from.
    private(set) var page: TerminalPage
    var input: Color
    var pending: Color
    var success: Color
    var failure: Color
    var user: Color
    /// ask's own messages: purple, whole block (roadmap 0106).
    var system: Color
    /// Secondary text, which the screen used to draw faint (SGR 2). Faint is left to the terminal and is often too weak on light and dark
    /// pages alike, so on a known page it is a grey four fifths of the way from the page to its text, or the text colour itself when that
    /// grey would read below 4.5:1 (low-contrast themes such as Solarized). On a guessed page it is nil and faint stays: a grey mixed for the
    /// wrong page could vanish, and the guess lasts only until the terminal answers its colour query.
    var secondary: Color?

    /// The tints for a light or a dark page, when the terminal's own colours are not known.
    public init(tinted: Bool = true, light: Bool = false) {
        self.init(tinted: tinted, page: light ? .light : .dark, known: false)
    }

    /// The tints mixed from `page`. `known` says the page is the terminal's own or one the person chose, not a guess.
    init(tinted: Bool = true, page: TerminalPage, known: Bool = true) {
        self.tinted = tinted
        self.page = page
        let light = page.isLight
        func mix(_ toward: SIMD3<Double>, _ share: Double) -> Color { page.tint(toward: toward, share: share) }
        // Shares tuned so text on every tint keeps at least 80% of the terminal's own contrast (WCAG 2 ratio) on Apple Terminal's Basic,
        // Solarized and One Light pages, while each tint stays visibly off the page; `TerminalColoursTests` checks both.
        input = mix(page.foreground, light ? 0.05 : 0.06)
        // The user's message is blue, bluer than anything else; a tool still running is grey (roadmap 0129).
        user = mix(Self.blue, 0.12)
        pending = mix(page.foreground, light ? 0.06 : 0.065)
        success = mix(Self.green, light ? 0.11 : 0.10)
        failure = mix(Self.red, 0.11)
        system = mix(Self.purple, 0.11)
        secondary = known ? page.secondaryText : nil
    }

    private static let blue = SIMD3<Double>(10, 132, 255)
    private static let green = SIMD3<Double>(52, 199, 89)
    private static let red = SIMD3<Double>(255, 69, 58)
    private static let purple = SIMD3<Double>(175, 82, 222)

    /// `style` as drawn: on a known page never faint, secondary text in ``secondary`` and coloured text at its full colour.
    func legible(_ style: Style) -> Style {
        guard style.dim, let secondary else { return style }
        var style = style
        style.dim = false
        if style.fg == .default { style.fg = secondary }
        return style
    }

    /// Every tint, for checks.
    var tints: [Color] { [input, user, pending, success, failure, system] }

    /// The background of a block of this kind: the user's messages and the tool calls are tinted (a tool by how it ended), nothing else is.
    func tint(for item: Transcript.Item) -> Color {
        guard tinted else { return .default }
        switch item {
            case .user: return user
            case .notice(_, let isError): return isError ? .default : system
            case .tool(_, _, let status, _, _):
                switch status {
                    case .running: return pending
                    case .succeeded: return success
                    case .failed: return failure
                }
            default: return .default
        }
    }

    /// The input's background, or the terminal's own when nothing is tinted.
    var inputBackground: Color { tinted ? input : .default }
}
