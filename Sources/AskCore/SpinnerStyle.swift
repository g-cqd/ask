/// The spinner drawn for progress and status (`ui.spinner`). `dot` and `star` are still read, so a file that names one loads, and are
/// drawn as the default spinner: they are no longer offered (roadmap 0171). Declared once for the setting and the screen (ADR-0166);
/// the frames are in AskTUI (`SpinnerStyle+Screen`).
public enum SpinnerStyle: String, Sendable, CaseIterable {
    case braille
    case braillefull
    case braillequarter
    case snake
    case line
    case dot
    case star
    case random

    /// The styles offered, in the `/config` editor and the catalog: every one but the two that are only still read.
    public static var allCases: [SpinnerStyle] {
        [.braille, .braillefull, .braillequarter, .snake, .line, .random]
    }

    /// The concrete styles, those `random` chooses among.
    public static let allConcrete: [SpinnerStyle] = [.braille, .braillefull, .braillequarter, .snake, .line]

    /// Whether this style is only still read: a file naming it loads, and the default is drawn instead.
    public var isOnlyRead: Bool { self == .dot || self == .star }
}
