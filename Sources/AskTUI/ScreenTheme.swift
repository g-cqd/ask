internal import Foundation
internal import TerminalKitStyle

/// The tints of the screen (roadmaps 0074 and 0108). A terminal has no alpha, so "a little off the page" is a colour mixed from the page itself:
/// the terminal's background, read with OSC 11, moved a few percent toward its foreground or a hue. A tint mixed from the real page keeps the
/// contrast the person chose for their terminal, light or dark, where fixed colours suit only the page they were picked on.
public struct ScreenTheme: Sendable, Equatable {
    /// Whether anything is tinted.
    public var tinted: Bool
    /// The page the tints were mixed from.
    public private(set) var page: Page
    var input: Color
    var pending: Color
    var success: Color
    var failure: Color
    var user: Color
    /// Secondary text, which the screen used to draw faint (SGR 2). Faint is left to the terminal and is often too weak on light and dark
    /// pages alike, so on a known page it is a grey four fifths of the way from the page to its text, or the text colour itself when that
    /// grey would read below 4.5:1 (low-contrast themes such as Solarized). On a guessed page it is nil and faint stays: a grey mixed for the
    /// wrong page could vanish, and the guess lasts only until the terminal answers its colour query.
    var secondary: Color?

    /// The terminal's colours, each channel 0 to 255. Without a foreground, the text is taken as black on a light page, white on a dark one.
    public struct Page: Sendable, Equatable {
        public var background: SIMD3<Double>
        public var foreground: SIMD3<Double>

        public init(background: SIMD3<Double>, foreground: SIMD3<Double>? = nil) {
            self.background = background
            self.foreground = foreground ?? (Self.luminance(background) > 0.4 ? .zero : SIMD3(repeating: 255))
        }

        /// A light page: white, as Apple Terminal's default profile in light mode.
        public static let light = Page(background: SIMD3(255, 255, 255))
        /// A dark page: Apple Terminal's default profile in dark mode is close to this grey.
        public static let dark = Page(background: SIMD3(30, 30, 30))

        /// Whether text on this page is dark, which is what makes a page light.
        public var isLight: Bool { Self.luminance(background) > Self.luminance(foreground) }

        /// Relative luminance (WCAG 2), 0 for black to 1 for white.
        static func luminance(_ color: SIMD3<Double>) -> Double {
            func linear(_ channel: Double) -> Double {
                let value = channel / 255
                return value <= 0.039_28 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * linear(color.x) + 0.7152 * linear(color.y) + 0.0722 * linear(color.z)
        }

        /// The WCAG 2 contrast ratio between two colours, 1 to 21.
        static func contrast(_ one: SIMD3<Double>, _ other: SIMD3<Double>) -> Double {
            let (a, b) = (luminance(one), luminance(other))
            return (Swift.max(a, b) + 0.05) / (Swift.min(a, b) + 0.05)
        }
    }

    /// The tints for a light or a dark page, when the terminal's own colours are not known.
    public init(tinted: Bool = true, light: Bool = false) {
        self.init(tinted: tinted, page: light ? .light : .dark, known: false)
    }

    /// The tints mixed from `page`. `known` says the page is the terminal's own or one the person chose, not a guess.
    public init(tinted: Bool = true, page: Page, known: Bool = true) {
        self.tinted = tinted
        self.page = page
        let light = page.isLight
        func mix(_ toward: SIMD3<Double>, _ share: Double) -> Color {
            let value = page.background + (toward - page.background) * share
            func channel(_ x: Double) -> UInt8 { UInt8(Swift.max(0, Swift.min(255, x.rounded()))) }
            return .rgb(r: channel(value.x), g: channel(value.y), b: channel(value.z))
        }
        // Shares tuned so text on every tint keeps at least 80% of the terminal's own contrast (WCAG 2 ratio) on Apple Terminal's Basic,
        // Solarized and One Light pages, while each tint stays visibly off the page; `TerminalColoursTests` checks both.
        input = mix(page.foreground, light ? 0.05 : 0.06)
        user = mix(page.foreground * 0.7 + Self.blue * 0.3, 0.09)
        pending = mix(Self.blue, light ? 0.07 : 0.08)
        success = mix(Self.green, light ? 0.11 : 0.10)
        failure = mix(Self.red, 0.11)
        let grey = page.background + (page.foreground - page.background) * 0.8
        secondary = !known ? nil : Page.contrast(grey, page.background) >= 4.5 ? mix(page.foreground, 0.8) : .default
    }

    private static let blue = SIMD3<Double>(10, 132, 255)
    private static let green = SIMD3<Double>(52, 199, 89)
    private static let red = SIMD3<Double>(255, 69, 58)

    /// `style` as drawn: on a known page never faint, secondary text in ``secondary`` and coloured text at its full colour.
    func legible(_ style: Style) -> Style {
        guard style.dim, let secondary else { return style }
        var style = style
        style.dim = false
        if style.fg == .default { style.fg = secondary }
        return style
    }

    /// Every tint, for checks.
    var tints: [Color] { [input, user, pending, success, failure] }

    /// The background of a block of this kind: the user's messages and the tool calls are tinted (a tool by how it ended), nothing else is.
    func tint(for item: Transcript.Item) -> Color {
        guard tinted else { return .default }
        switch item {
            case .user: return user
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
