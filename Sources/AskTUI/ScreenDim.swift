internal import TerminalKitCodecs

/// How faint secondary text is drawn (`ui.dim`, note n13): the share of the way from the page to its text its grey sits at.
public enum ScreenDim: String, Sendable, Equatable {
    case normal, faint, fainter

    /// How far from the page toward the text the grey sits.
    var share: Double {
        switch self {
            case .normal: 0.8
            case .faint: 0.65
            case .fainter: 0.5
        }
    }

    /// The least contrast with the page it may read at: the person who asks for fainter text takes less, never so little it is lost.
    private var leastContrast: Double { self == .normal ? 4.5 : 3 }

    /// The grey for secondary text on `page`: this level's, or ask's own when this one would read below its least contrast, or the
    /// text colour itself (``Color/default``) when even that would.
    func secondary(on page: TerminalPage) -> Color {
        let grey = page.background + (page.foreground - page.background) * share
        guard self != .normal, TerminalPage.contrast(grey, page.background) >= leastContrast else {
            return page.secondaryText
        }
        return page.tint(toward: page.foreground, share: share)
    }
}
