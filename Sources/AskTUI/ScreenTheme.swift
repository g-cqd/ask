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
    /// How faint secondary text is (`ui.dim`).
    private(set) var dim: ScreenDim

    /// A shimmering header's own text (roadmap 0187), drawn dim as well: three quarters of the way from the page to the text, so with dim
    /// on top it is fainter than a dim header, and the bright stretch stands out.
    var shimmerBase: Color { page.tint(toward: page.foreground, share: dim.share - 0.05) }
    /// The stretch's edges, the softer step between the faint header and the bold core.
    var shimmerEdge: Color { page.secondaryText }
    var input: Color
    var pending: Color
    var success: Color
    var failure: Color
    var user: Color
    /// ask's own messages: purple, whole block (roadmap 0106).
    var system: Color
    /// What the person interrupted: orange, apart from a failure's red (roadmap 0142).
    var interrupted: Color
    /// A `/btw` aside (roadmap 0194): cyan, a colour no other block takes.
    var aside: Color
    /// The rows an edit removes and adds (roadmap 0152): red and green, deeper than a block's own tint so they stand out on it.
    var diffRemoved: Color
    var diffAdded: Color
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
    init(tinted: Bool = true, page: TerminalPage, known: Bool = true, dim: ScreenDim = .normal) {
        self.tinted = tinted
        self.page = page
        self.dim = dim
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
        interrupted = mix(Self.orange, 0.11)
        aside = mix(Self.cyan, 0.11)
        // As deep as the contrast rule above allows: green is the bright hue, and a dark page takes little more of it than a
        // succeeded block's own tint, so there the marker carries most of the difference.
        diffRemoved = mix(Self.red, 0.16)
        diffAdded = mix(Self.green, light ? 0.2 : 0.11)
        secondary = known ? dim.secondary(on: page) : nil
    }

    private static let blue = SIMD3<Double>(10, 132, 255)
    private static let green = SIMD3<Double>(52, 199, 89)
    private static let red = SIMD3<Double>(255, 69, 58)
    private static let purple = SIMD3<Double>(175, 82, 222)
    private static let orange = SIMD3<Double>(255, 149, 0)
    private static let cyan = SIMD3<Double>(50, 173, 230)

    /// `style` as drawn: on a known page never faint, secondary text in ``secondary`` and coloured text at its full colour.
    func legible(_ style: Style) -> Style {
        guard style.dim, let secondary else { return style }
        var style = style
        style.dim = false
        if style.fg == .default { style.fg = secondary }
        return style
    }

    /// The status line's background for a session seeded by `seed` (roadmap 0164): its hue, mixed into the page a little more than the
    /// block tints are, so it reads as the session's colour while its text keeps the terminal's contrast.
    func sessionTint(seed: String) -> Color { page.tint(toward: SessionHue.rgb(seed: seed), share: 0.16) }

    /// The box around the input (`ui.inputBorder`, note n36): the session's hue, lighter, mixed most of the way from the page so it reads
    /// as the session's colour without the weight of text; the grey of secondary text when asked, or while the session has no colour yet.
    func inputBorder(_ look: ScreenInputBorder, seed: String?) -> Style {
        guard look == .tint, let seed else { return Style(dim: true) }
        return Style(fg: page.tint(toward: SessionHue.rgb(seed: seed), share: 0.6))
    }

    /// Every tint, for checks.
    var tints: [Color] { [input, user, pending, success, failure, system, interrupted, aside, diffRemoved, diffAdded] }

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
                    case .interrupted: return interrupted
                }
            default: return .default
        }
    }

    /// The input's background, or the terminal's own when nothing is tinted.
    var inputBackground: Color { tinted ? input : .default }
}
